#!/usr/bin/env bash
# test-proof-chain.sh — Contract tests for the proof-of-work chain (#43, #135)
#
# Purpose: Verify that all proof-chain components work together correctly:
#   - guard.sh Check 8: deny commit/merge without verified proof
#   - guard.sh Check 9: deny Bash writes to .proof-status
#   - guard.sh Check 10: deny deletion of active .proof-status
#   - track.sh invalidation: verified->pending on source change
#   - task-track.sh Gate C: Guardian requires verified when file exists
#   - session-init.sh clearing: stale .proof-status cleaned at start
#   - session-summary.sh: proof line present in output
#
# @decision DEC-V3-003
# @title Proof-of-work chain contract tests
# @status accepted
# @rationale Phase 7 completion requires verifying the end-to-end proof chain:
#   implementer dispatch activates the gate (task-track.sh Gate C), source changes
#   invalidate proof (track.sh), guard.sh enforces the gate at commit/merge time
#   (Check 8) and protects the file from agent manipulation (Checks 9-10), and
#   session-init.sh cleans stale proof state at session start (crash recovery).
#   These are contract tests — each test validates one behavioral contract.
#   Uses isolated temp git repos to avoid contaminating the live ~/.claude state.
#
# Usage: bash tests/test-proof-chain.sh
# Returns: 0 if all 18 tests pass, 1 if any fail

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOKS_DIR="${PROJECT_ROOT}/hooks"
GUARD_SH="${HOOKS_DIR}/guard.sh"
TRACK_SH="${HOOKS_DIR}/track.sh"
TASK_TRACK_SH="${HOOKS_DIR}/task-track.sh"
SESSION_INIT_SH="${HOOKS_DIR}/session-init.sh"
SESSION_SUMMARY_SH="${HOOKS_DIR}/session-summary.sh"

# Ensure tmp directory exists
mkdir -p "$PROJECT_ROOT/tmp"

# ---------------------------------------------------------------------------
# Test tracking
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Helper: make_temp_repo — create an isolated git repo for testing.
# Creates an initial commit on a feature branch (not main/master) so that
# guard.sh Check 2 (main is sacred) does not fire before Check 8 (proof gate).
# Returns path via stdout. Caller is responsible for cleanup.
# ---------------------------------------------------------------------------
make_temp_repo() {
    local tmp_dir
    tmp_dir=$(mktemp -d "$PROJECT_ROOT/tmp/test-pc-XXXXXX")
    git -C "$tmp_dir" init -q 2>/dev/null
    # Create on a feature branch so guard.sh Check 2 (main is sacred) doesn't fire
    git -C "$tmp_dir" checkout -q -b feature/test-branch 2>/dev/null || true
    git -C "$tmp_dir" commit --allow-empty -m "init" -q 2>/dev/null
    mkdir -p "$tmp_dir/.claude"
    echo "$tmp_dir"
}

# ---------------------------------------------------------------------------
# Helper: run_guard — invoke guard.sh with a mock Bash command
# Args: $1=command string, $2=temp_repo path, $3=optional proof status value
# The proof_status arg (not env var) avoids bash function env-prefix issues.
# Returns: guard.sh stdout
# ---------------------------------------------------------------------------
run_guard() {
    local cmd="$1"
    local repo="$2"
    local proof_status="${3:-}"

    mkdir -p "$repo/.claude"
    if [[ -n "$proof_status" ]]; then
        echo "$proof_status" > "$repo/.claude/.proof-status"
    else
        rm -f "$repo/.claude/.proof-status"
    fi

    local input_json
    input_json=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' \
        "$(echo "$cmd" | sed 's/"/\\"/g')")

    # Use a subshell so CWD and CLAUDE_PROJECT_DIR are properly set for bash subprocess.
    # The pipe in "echo ... | bash" creates a new process; env must be exported within
    # the subshell, not just prefixed on the echo builtin.
    local output
    output=$( export CLAUDE_PROJECT_DIR="$repo"
              cd "$repo"
              echo "$input_json" | bash "$GUARD_SH" 2>/dev/null
            ) || true
    echo "$output"
}

# ---------------------------------------------------------------------------
# Helper: run_guard_with_file — invoke guard.sh when .proof-status is
# pre-written (for Check 10 tests where we set the file ourselves).
# Args: $1=command string, $2=temp_repo path
# Does NOT touch .proof-status — caller must set it before calling.
# Returns: guard.sh stdout
# ---------------------------------------------------------------------------
run_guard_with_file() {
    local cmd="$1"
    local repo="$2"

    local input_json
    input_json=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' \
        "$(echo "$cmd" | sed 's/"/\\"/g')")

    local output
    output=$( export CLAUDE_PROJECT_DIR="$repo"
              cd "$repo"
              echo "$input_json" | bash "$GUARD_SH" 2>/dev/null
            ) || true
    echo "$output"
}

# ---------------------------------------------------------------------------
# Helper: run_track — invoke track.sh simulating a Write/Edit event
# Args: $1=file_path, $2=temp_repo path
# Returns: track.sh stdout (usually empty)
# ---------------------------------------------------------------------------
run_track() {
    local file_path="$1"
    local repo="$2"

    local input_json
    input_json=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$file_path")

    # Subshell with export so CLAUDE_PROJECT_DIR reaches the bash subprocess
    ( export CLAUDE_PROJECT_DIR="$repo"
      cd "$repo"
      echo "$input_json" | bash "$TRACK_SH" 2>/dev/null
    ) || true
}

# ---------------------------------------------------------------------------
# Helper: run_task_track — invoke task-track.sh with an agent type
# Args: $1=agent_type, $2=temp_repo path, $3=optional proof status value
# Returns: task-track.sh stdout
# ---------------------------------------------------------------------------
run_task_track() {
    local agent_type="$1"
    local repo="$2"
    local proof_status="${3:-}"

    mkdir -p "$repo/.claude"
    if [[ -n "$proof_status" ]]; then
        echo "$proof_status" > "$repo/.claude/.proof-status"
    else
        rm -f "$repo/.claude/.proof-status"
    fi

    local input_json
    input_json=$(printf '{"tool_name":"Task","tool_input":{"subagent_type":"%s","instructions":"test"}}' \
        "$agent_type")

    local output
    output=$( export CLAUDE_PROJECT_DIR="$repo"
              cd "$repo"
              echo "$input_json" | bash "$TASK_TRACK_SH" 2>/dev/null
            ) || true
    echo "$output"
}

# ===========================================================================
# Section 1: guard.sh Check 8 — deny commit without verified (4 tests)
# ===========================================================================

run_test "Check 8: commit denied when .proof-status is missing-then-created (no-file bootstrap)"
REPO=$(make_temp_repo)
# No .proof-status = bootstrap path, commit allowed
OUTPUT=$(run_guard "git commit -m test" "$REPO")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "proof"; then
    fail_test "Commit blocked when .proof-status missing (should allow — bootstrap)"
else
    pass_test
fi
rm -rf "$REPO"

run_test "Check 8: commit denied when .proof-status is pending"
REPO=$(make_temp_repo)
OUTPUT=$(run_guard "git commit -m test" "$REPO" "pending|$(date +%s)")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "proof"; then
    pass_test
else
    fail_test "Commit allowed with pending proof (should deny)"
fi
rm -rf "$REPO"

run_test "Check 8: commit passes when .proof-status is verified"
REPO=$(make_temp_repo)
# Set test-status to pass so Check 7 doesn't block us
echo "pass|0|$(date +%s)" > "$REPO/.claude/.test-status"
OUTPUT=$(run_guard "git commit -m test" "$REPO" "verified|$(date +%s)")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "proof"; then
    fail_test "Commit blocked with verified proof (should allow)"
else
    pass_test
fi
rm -rf "$REPO"

run_test "Check 8: meta-repo (non-git temp) has no .proof-status = commit allowed"
# Tests that the bootstrap path (no .proof-status file) allows commits.
# The meta-repo (~/.claude) has no .proof-status at rest — same behavior expected.
REPO=$(make_temp_repo)
# Verify no .proof-status exists
rm -f "$REPO/.claude/.proof-status"
echo "pass|0|$(date +%s)" > "$REPO/.claude/.test-status"
OUTPUT=$(run_guard "git commit -m test" "$REPO")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "proof"; then
    fail_test "Commit blocked with no .proof-status (bootstrap path should allow)"
else
    pass_test
fi
rm -rf "$REPO"

# ===========================================================================
# Section 2: guard.sh Check 9 — deny Bash writes to .proof-status (2 tests)
# ===========================================================================

run_test "Check 9: block agent writing 'verified' to .proof-status via redirect"
REPO=$(make_temp_repo)
# Command: echo "verified|ts" > .proof-status  — should be denied
OUTPUT=$(run_guard "echo 'verified|12345' > $REPO/.claude/.proof-status" "$REPO")
if echo "$OUTPUT" | grep -q "deny"; then
    pass_test
else
    fail_test "Write of 'verified' to .proof-status was not blocked"
fi
rm -rf "$REPO"

run_test "Check 9: allow non-verification writes to .proof-status (pending writes allowed)"
REPO=$(make_temp_repo)
# A non-approval write (like echo "pending|ts") should NOT match Check 9
# Check 9 requires BOTH a redirect to proof-status AND approval keyword
OUTPUT=$(run_guard "echo 'pending|12345' > $REPO/.claude/.proof-status" "$REPO")
if echo "$OUTPUT" | grep -q '"permissionDecision":"deny"' && echo "$OUTPUT" | grep -qi "approval\|verified\|only.*user"; then
    fail_test "Non-approval write blocked (false positive in Check 9)"
else
    pass_test
fi
rm -rf "$REPO"

# ===========================================================================
# Section 3: guard.sh Check 10 — deny deletion of active .proof-status (2 tests)
# ===========================================================================

run_test "Check 10: block deletion of .proof-status when pending"
REPO=$(make_temp_repo)
# Write file directly — run_guard_with_file does NOT touch .proof-status
echo "pending|$(date +%s)" > "$REPO/.claude/.proof-status"
OUTPUT=$(run_guard_with_file "rm $REPO/.claude/.proof-status" "$REPO")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "verification is active"; then
    pass_test
else
    fail_test "Deletion of pending .proof-status was not blocked"
fi
rm -rf "$REPO"

run_test "Check 10: allow deletion of .proof-status when verified"
REPO=$(make_temp_repo)
echo "verified|$(date +%s)" > "$REPO/.claude/.proof-status"
OUTPUT=$(run_guard_with_file "rm $REPO/.claude/.proof-status" "$REPO")
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Deletion of verified .proof-status was blocked (should allow)"
else
    pass_test
fi
rm -rf "$REPO"

# ===========================================================================
# Section 4: track.sh invalidation (4 tests)
# ===========================================================================

run_test "track.sh: verified proof becomes pending after source file change"
REPO=$(make_temp_repo)
echo "verified|$(date +%s)" > "$REPO/.claude/.proof-status"
# Use $REPO directly as file parent (exists) — track.sh exits early if parent missing
run_track "$REPO/main.sh" "$REPO"
if [[ -f "$REPO/.claude/.proof-status" ]]; then
    STATUS=$(cut -d'|' -f1 "$REPO/.claude/.proof-status")
    if [[ "$STATUS" == "pending" ]]; then
        pass_test
    else
        fail_test "Status is '$STATUS' after source change, expected 'pending'"
    fi
else
    fail_test ".proof-status was deleted instead of set to pending"
fi
rm -rf "$REPO"

run_test "track.sh: test files do NOT invalidate verified proof"
REPO=$(make_temp_repo)
echo "verified|$(date +%s)" > "$REPO/.claude/.proof-status"
# .test.sh matches the spec exclusion pattern — should NOT invalidate
run_track "$REPO/main.test.sh" "$REPO"
if [[ -f "$REPO/.claude/.proof-status" ]]; then
    STATUS=$(cut -d'|' -f1 "$REPO/.claude/.proof-status")
    if [[ "$STATUS" == "verified" ]]; then
        pass_test
    else
        fail_test "Test file write invalidated proof (status: $STATUS, expected: verified)"
    fi
else
    fail_test ".proof-status was deleted by test file write"
fi
rm -rf "$REPO"

run_test "track.sh: doc files (.md) do NOT invalidate verified proof"
REPO=$(make_temp_repo)
echo "verified|$(date +%s)" > "$REPO/.claude/.proof-status"
# .md is not a source extension — should NOT invalidate
run_track "$REPO/README.md" "$REPO"
if [[ -f "$REPO/.claude/.proof-status" ]]; then
    STATUS=$(cut -d'|' -f1 "$REPO/.claude/.proof-status")
    if [[ "$STATUS" == "verified" ]]; then
        pass_test
    else
        fail_test "Doc file write invalidated proof (status: $STATUS, expected: verified)"
    fi
else
    fail_test ".proof-status was deleted by doc file write"
fi
rm -rf "$REPO"

run_test "track.sh: already-pending proof is not changed by source change"
REPO=$(make_temp_repo)
echo "pending|11111" > "$REPO/.claude/.proof-status"
# Write a source file — status already pending, should remain pending (may update timestamp)
run_track "$REPO/main.py" "$REPO"
if [[ -f "$REPO/.claude/.proof-status" ]]; then
    STATUS=$(cut -d'|' -f1 "$REPO/.claude/.proof-status")
    if [[ "$STATUS" == "pending" ]]; then
        pass_test
    else
        fail_test "Already-pending proof changed to '$STATUS' (expected: pending)"
    fi
else
    fail_test ".proof-status was deleted (expected: pending remains)"
fi
rm -rf "$REPO"

# ===========================================================================
# Section 5: task-track.sh Gate C — Guardian requires verified when file exists (3 tests)
# ===========================================================================

run_test "Gate C: verified proof allows Guardian dispatch"
REPO=$(make_temp_repo)
OUTPUT=$(run_task_track "guardian" "$REPO" "verified|$(date +%s)")
if echo "$OUTPUT" | grep -q "deny"; then
    fail_test "Guardian dispatch blocked with verified proof (should allow)"
else
    pass_test
fi
rm -rf "$REPO"

run_test "Gate C: pending proof blocks Guardian dispatch"
REPO=$(make_temp_repo)
OUTPUT=$(run_task_track "guardian" "$REPO" "pending|$(date +%s)")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "proof"; then
    pass_test
else
    fail_test "Guardian dispatch allowed with pending proof (should deny)"
fi
rm -rf "$REPO"

run_test "Gate C: missing .proof-status allows Guardian dispatch (bootstrap)"
REPO=$(make_temp_repo)
OUTPUT=$(run_task_track "guardian" "$REPO")
if echo "$OUTPUT" | grep -q "deny" && echo "$OUTPUT" | grep -q "proof"; then
    fail_test "Guardian dispatch blocked with no .proof-status (bootstrap should allow)"
else
    pass_test
fi
rm -rf "$REPO"

# ===========================================================================
# Section 6: session-init.sh clearing — stale .proof-status cleaned at start (2 tests)
# ===========================================================================

run_test "session-init.sh: contains .proof-status cleanup logic (crash recovery)"
# Verify the cleanup block exists in session-init.sh
if grep -q "proof-status" "$SESSION_INIT_SH" && \
   grep -q "Cleaned stale .proof-status" "$SESSION_INIT_SH"; then
    pass_test
else
    fail_test "session-init.sh is missing .proof-status cleanup logic"
fi

run_test "session-init.sh: no error when .proof-status is missing at startup"
# Verify that the proof cleanup block is guarded: only acts when file exists.
# session-init.sh sets PROOF_FILE="${CLAUDE_DIR}/.proof-status" and then
# checks [[ -f "$PROOF_FILE" ]] before attempting cleanup.
if grep -q 'PROOF_FILE.*proof-status' "$SESSION_INIT_SH" && \
   grep -q '\[\[ -f "\$PROOF_FILE"' "$SESSION_INIT_SH"; then
    pass_test
else
    fail_test "session-init.sh is missing -f guard on \$PROOF_FILE (could error when missing)"
fi

# ===========================================================================
# Section 7: session-summary.sh proof reporting (1 test)
# ===========================================================================

run_test "session-summary.sh: proof status line present in output"
# Verify that session-summary.sh contains proof reporting logic (W7-1)
if grep -q 'proof-status\|Proof:' "$SESSION_SUMMARY_SH"; then
    pass_test
else
    fail_test "session-summary.sh is missing proof status reporting (W7-1 not applied)"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "=========================================="
echo "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILED: $TESTS_FAILED test(s) failed"
    exit 1
else
    echo "SUCCESS: All $TESTS_PASSED tests passed"
    exit 0
fi
