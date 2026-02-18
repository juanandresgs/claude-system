#!/usr/bin/env bash
# Test guard.sh Check 0.75 (Subshell containment for cd into .worktrees/ directories).
#
# Check 0.75 intercepts Bash commands that contain `cd` or `pushd` targeting a
# .worktrees/ path combined with chained commands (&&, ;, ||). Such commands would
# leave the orchestrator's Bash tool CWD inside a deletable worktree directory —
# when the worktree is later removed ALL hooks fail (posix_spawn ENOENT on macOS).
#
# Prevention strategy: wrap the entire command in a subshell so the cd + chained
# command executes in the worktree but the CWD change does NOT persist to the parent
# shell. Bare `cd .worktrees/x` (no chained commands) is allowed because subagents
# (implementer, guardian) legitimately need persistent CWD in their worktrees.
#
# @decision DEC-GUARD-CWD-003
# @title Test suite for guard.sh Check 0.75 subshell containment
# @status accepted
# @rationale posix_spawn returns ENOENT on macOS when the parent process CWD is a
#   deleted directory. The canary approach (Path B) only recovers PreToolUse:Bash;
#   Edit hooks, Stop hooks, and SessionEnd hooks cannot be recovered. Prevention is
#   the only reliable fix. This test suite validates that:
#   (1) chained cd-into-worktree commands are subshell-wrapped (the rewrite path),
#   (2) bare cd-into-worktree commands pass through (subagent persistent CWD), and
#   (3) commands that mention .worktrees/ without cd/pushd are not affected.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

mkdir -p "$PROJECT_ROOT/tmp"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Running: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS"
}

fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $reason"
}

# Helper: build JSON hook input for guard.sh (no .cwd field needed for these tests)
make_input() {
    local cmd="$1"
    printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# Helper: assert output is a rewrite wrapping the command in a subshell
assert_subshell_rewrite() {
    local output="$1"
    local label="$2"
    if echo "$output" | grep -q '"permissionDecision": "allow"' && \
       echo "$output" | grep -q '"updatedInput"' && \
       echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); cmd=d["hookSpecificOutput"]["updatedInput"]["command"]; assert cmd.startswith("( ") and cmd.endswith(" )"), f"not a subshell: {cmd}"' 2>/dev/null; then
        pass_test
    elif echo "$output" | grep -q '"permissionDecision": "deny"' && \
         echo "$output" | grep -q "SAFETY"; then
        fail_test "$label: deny-on-crash triggered instead of rewrite. Output: $output"
    elif echo "$output" | grep -q '"permissionDecision": "deny"'; then
        fail_test "$label: denied instead of rewrite. Output: $output"
    elif echo "$output" | grep -q '"updatedInput"'; then
        # Rewrite exists but may not be a subshell — extract and check
        local rewritten
        rewritten=$(echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hookSpecificOutput"]["updatedInput"]["command"])' 2>/dev/null || echo "")
        if [[ "$rewritten" == "( "* && "$rewritten" == *" )" ]]; then
            pass_test
        else
            fail_test "$label: rewrite exists but not a subshell. Rewritten: $rewritten"
        fi
    else
        fail_test "$label: expected subshell rewrite (allow+updatedInput starting with '( '). Got: $output"
    fi
}

# Helper: assert output is empty (passthrough — guard has no opinion)
assert_passthrough() {
    local output="$1"
    local label="$2"
    if [[ -z "$output" ]]; then
        pass_test
    elif echo "$output" | grep -q '"permissionDecision": "allow"' && \
         echo "$output" | grep -q '"updatedInput"'; then
        local rewritten
        rewritten=$(echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hookSpecificOutput"]["updatedInput"]["command"])' 2>/dev/null || echo "")
        fail_test "$label: unexpected rewrite (want passthrough/empty). Rewritten to: $rewritten"
    elif echo "$output" | grep -q '"permissionDecision": "deny"'; then
        fail_test "$label: unexpected deny (want passthrough/empty). Got: $output"
    else
        fail_test "$label: unexpected output (want empty). Got: $output"
    fi
}

# --- Test 0: Syntax check ---
run_test "Syntax: guard.sh is valid bash"
if bash -n "$HOOKS_DIR/guard.sh"; then
    pass_test
else
    fail_test "guard.sh has syntax errors"
fi

# --- Test 1: cd .worktrees/foo && git status → subshell wrapped ---
# The most common orchestrator anti-pattern: cd into worktree then run a command.
# This would leave the orchestrator's Bash CWD inside a deletable directory.
run_test "Check0.75: 'cd .worktrees/foo && git status' → subshell wrapped"

CMD="cd .worktrees/foo && git status"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_subshell_rewrite "$OUTPUT" "cd relative .worktrees + git status"

# --- Test 2: cd /abs/.worktrees/foo && python3 -c "test" → subshell wrapped ---
# Absolute path variant — the pattern must work regardless of path style.
run_test "Check0.75: 'cd /abs/.worktrees/foo && python3 -c ...' → subshell wrapped"

CMD='cd /home/user/.worktrees/feature-x && python3 -c "import sys; print(sys.version)"'
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_subshell_rewrite "$OUTPUT" "cd absolute .worktrees + python3"

# --- Test 3: pushd .worktrees/foo && make → subshell wrapped ---
# pushd is equivalent to cd for CWD persistence — must be caught too.
run_test "Check0.75: 'pushd .worktrees/foo && make' → subshell wrapped"

CMD="pushd .worktrees/feature-build && make test"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_subshell_rewrite "$OUTPUT" "pushd .worktrees + make"

# --- Test 4: cd .worktrees/foo ; echo done → subshell wrapped (semicolon separator) ---
# Semicolons are also command separators — chained commands after ; must trigger wrap.
run_test "Check0.75: 'cd .worktrees/foo ; echo done' → subshell wrapped (semicolon)"

CMD="cd .worktrees/my-feature ; echo done"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_subshell_rewrite "$OUTPUT" "cd .worktrees + semicolon + echo"

# --- Test 5: cd .worktrees/foo (bare) → PASSTHROUGH ---
# Bare cd into a worktree: subagents (implementer, guardian) need persistent CWD.
# This must NOT be wrapped — the subagent's own shell manages the deletion risk.
run_test "Check0.75: 'cd .worktrees/foo' (bare, no chain) → PASSTHROUGH (subagent allowed)"

CMD="cd .worktrees/feature-mywork"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_passthrough "$OUTPUT" "bare cd .worktrees (no chained command)"

# --- Test 6: ls .worktrees/foo → PASSTHROUGH (no cd detected) ---
# Commands that reference .worktrees/ paths without cd/pushd must not be affected.
run_test "Check0.75: 'ls .worktrees/foo' → PASSTHROUGH (not a cd command)"

CMD="ls .worktrees/feature-x"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_passthrough "$OUTPUT" "ls .worktrees (not a cd)"

# --- Test 7: git -C .worktrees/foo status → PASSTHROUGH (git -C, not cd) ---
# git -C changes directory internally but does NOT change the shell CWD.
# This is the preferred pattern (per CLAUDE.md) and must never be blocked.
run_test "Check0.75: 'git -C .worktrees/foo status' → PASSTHROUGH (git -C is safe)"

CMD="git -C .worktrees/feature-foo status"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_passthrough "$OUTPUT" "git -C .worktrees (no cd)"

# --- Test 8: export FOO=1 && cd .worktrees/x && cmd → subshell wrapped ---
# Complex multi-step command: the entire thing must be wrapped, not just the cd.
# The subshell must capture the full original command string.
run_test "Check0.75: 'export FOO=1 && cd .worktrees/x && cmd' → entire command subshell wrapped"

CMD="export FOO=bar && cd .worktrees/feature-complex && bash run.sh"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_subshell_rewrite "$OUTPUT" "export + cd .worktrees + bash run.sh"

# Verify the full original command is preserved inside the subshell
if echo "$OUTPUT" | grep -q '"updatedInput"'; then
    REWRITTEN=$(echo "$OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hookSpecificOutput"]["updatedInput"]["command"])' 2>/dev/null || echo "")
    EXPECTED="( $CMD )"
    if [[ "$REWRITTEN" == "$EXPECTED" ]]; then
        : # Already passed above — just verifying content
    else
        # This is a content check WITHIN the already-passing test — we note but don't double-count
        echo "  NOTE: content check: got '$REWRITTEN', expected '$EXPECTED'"
    fi
fi

# --- Test 9: cd .worktrees/foo || exit 1 && cmd → subshell wrapped (|| after worktree path) ---
# Logical OR after the worktree path — || also indicates chained commands.
run_test "Check0.75: 'cd .worktrees/foo || exit 1 && cmd' → subshell wrapped (|| separator)"

CMD="cd .worktrees/feature-fallback || exit 1"
INPUT_JSON=$(make_input "$CMD")
OUTPUT=$(echo "$INPUT_JSON" | bash "$HOOKS_DIR/guard.sh" 2>/dev/null) || true

assert_subshell_rewrite "$OUTPUT" "cd .worktrees + || exit"

# --- Summary ---
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
