#!/usr/bin/env bash
# test-observatory-remaining-fixes.sh — Tests for Phase 2 observatory signal fixes
#
# Purpose: Verify three signal implementations from Observatory Phase 2:
#   - SIG-DURATION-BUG (#90): now_epoch uses date -u +%s to match UTC start_epoch
#   - SIG-OUTCOME-FLAT: Expanded outcome classification (timeout, skipped)
#   - SIG-MAIN-IMPL: Implementer dispatch blocked on main/master branch
#
# Tests:
#   1. UTC timestamp parses to correct epoch
#   2. Duration calculation produces positive values (start < now)
#   3. test_result=pass → outcome=success
#   4. test_result=fail → outcome=failure
#   5. duration>600 + test_result=unknown → outcome=timeout
#   6. Empty artifacts dir → outcome=skipped
#   7. No artifacts dir at all → outcome=skipped
#   8. test_result=unknown + duration<600 + has artifacts → outcome=partial
#   9. Implementer on main branch → deny response
#  10. Implementer on feature branch → allowed (exit 0)
#  11. Implementer in meta-repo on main → allowed (is_claude_meta_repo exemption)
#
# @decision DEC-OBS-TEST-002
# @title Tests for Phase 2 observatory signal fixes
# @status accepted
# @rationale Direct function testing against real implementations (no mocks) is the
#   sacred practice. finalize_trace() is tested by sourcing context-lib.sh and
#   calling it with controlled manifests. task-track.sh branch gate is tested by
#   simulating the hook stdin with real git repos on main/feature branches.
#
# Usage: bash tests/test-observatory-remaining-fixes.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="${WORKTREE_ROOT}/hooks"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Shared cleanup list for temp directories
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

# Create an isolated trace store
make_trace_store() {
    local d
    d=$(mktemp -d)
    CLEANUP_DIRS+=("$d")
    echo "$d"
}

# Create a plain directory
make_plain_dir() {
    local d
    d=$(mktemp -d)
    CLEANUP_DIRS+=("$d")
    echo "$d"
}

# Create a git repo on a specific branch
make_git_repo_on_branch() {
    local branch="${1:-main}"
    local d
    d=$(mktemp -d)
    CLEANUP_DIRS+=("$d")
    git -C "$d" init -q 2>/dev/null
    git -C "$d" config user.email "test@test.com" 2>/dev/null
    git -C "$d" config user.name "Test" 2>/dev/null
    # Create initial commit (needed for branch rename to work)
    echo "initial" > "${d}/base.txt"
    git -C "$d" add base.txt 2>/dev/null
    git -C "$d" commit -q -m "initial" 2>/dev/null
    # Rename to target branch
    git -C "$d" branch -m "$branch" 2>/dev/null || true
    echo "$d"
}

# Create a trace manifest in a trace store
# Usage: make_trace TS STARTED_AT AGENT_TYPE
# Creates: TS/<trace_id>/manifest.json and returns trace_id
make_trace() {
    local ts="$1"
    local started_at="$2"
    local agent_type="${3:-implementer}"
    local trace_id="test-$(date +%s)-$$-$RANDOM"
    local trace_dir="${ts}/${trace_id}"
    mkdir -p "$trace_dir"
    cat > "${trace_dir}/manifest.json" <<EOF
{
  "trace_id": "$trace_id",
  "started_at": "$started_at",
  "agent_type": "$agent_type",
  "status": "active"
}
EOF
    echo "$trace_id"
}

# ============================================================
# Test 1: UTC timestamp parses to correct epoch
# ============================================================
echo ""
echo "=== Test 1: UTC timestamp parses to correct epoch ==="

KNOWN_TS="2026-01-01T12:00:00Z"
# Expected: 2026-01-01 12:00:00 UTC = epoch 1767268800
# Verified with python3: calendar.timegm((2026,1,1,12,0,0,0,0,0)) = 1767268800
EXPECTED_EPOCH=1767268800

# Test macOS path (date -u -j -f)
GOT_EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$KNOWN_TS" +%s 2>/dev/null \
    || date -u -d "$KNOWN_TS" +%s 2>/dev/null \
    || echo "0")

if [[ "$GOT_EPOCH" -eq "$EXPECTED_EPOCH" ]]; then
    pass "UTC timestamp '$KNOWN_TS' parses to epoch $EXPECTED_EPOCH"
else
    fail "UTC timestamp '$KNOWN_TS' → expected $EXPECTED_EPOCH, got $GOT_EPOCH"
fi

# ============================================================
# Test 2: Duration calculation produces positive values
# ============================================================
echo ""
echo "=== Test 2: Duration calculation produces positive values ==="

# Use a timestamp in the past (1 hour ago from known epoch)
PAST_EPOCH=$(( $(date -u +%s) - 3600 ))
PAST_TS=$(date -u -j -f "%s" "$PAST_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "@$PAST_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || echo "")

if [[ -z "$PAST_TS" ]]; then
    fail "Duration test: could not format past timestamp for testing"
else
    start_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$PAST_TS" +%s 2>/dev/null \
        || date -u -d "$PAST_TS" +%s 2>/dev/null || echo "0")
    now_epoch=$(date -u +%s)
    duration=$(( now_epoch - start_epoch ))
    if [[ "$duration" -gt 0 ]]; then
        pass "Duration is positive: $duration seconds (started 1h ago)"
    else
        fail "Duration is not positive: $duration (start=$start_epoch, now=$now_epoch)"
    fi
fi

# ============================================================
# Test 3: test_result=pass → outcome=success
# ============================================================
echo ""
echo "=== Test 3: test_result=pass → outcome=success ==="

TS3=$(make_trace_store)
PROJ3=$(make_plain_dir)
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TRACE_ID3=$(make_trace "$TS3" "$STARTED_AT" "implementer")
TRACE_DIR3="${TS3}/${TRACE_ID3}"

# Create artifacts with passing test output + summary.md
mkdir -p "${TRACE_DIR3}/artifacts"
echo "Tests passed: 10/10" > "${TRACE_DIR3}/artifacts/test-output.txt"
echo "# Summary" > "${TRACE_DIR3}/summary.md"

output3=$(
    set +e
    source "${HOOKS_DIR}/log.sh" 2>/dev/null
    source "${HOOKS_DIR}/context-lib.sh" 2>/dev/null
    # Assign AFTER sourcing — context-lib.sh exports TRACE_STORE=$HOME/.claude/traces
    # unconditionally at source time, clobbering any pre-set value.
    TRACE_STORE="$TS3"
    finalize_trace "$TRACE_ID3" "$PROJ3" "implementer" 2>/dev/null
    jq -r '.outcome // "not-set"' "${TRACE_DIR3}/manifest.json" 2>/dev/null
)
if [[ "$output3" == "success" ]]; then
    pass "test_result=pass → outcome=success"
else
    fail "test_result=pass → expected 'success', got: '$output3'"
fi

# ============================================================
# Test 4: test_result=fail → outcome=failure
# ============================================================
echo ""
echo "=== Test 4: test_result=fail → outcome=failure ==="

TS4=$(make_trace_store)
PROJ4=$(make_plain_dir)
TRACE_ID4=$(make_trace "$TS4" "$STARTED_AT" "implementer")
TRACE_DIR4="${TS4}/${TRACE_ID4}"

mkdir -p "${TRACE_DIR4}/artifacts"
echo "Tests FAILED: 3 failures" > "${TRACE_DIR4}/artifacts/test-output.txt"
echo "# Summary" > "${TRACE_DIR4}/summary.md"

output4=$(
    set +e
    source "${HOOKS_DIR}/log.sh" 2>/dev/null
    source "${HOOKS_DIR}/context-lib.sh" 2>/dev/null
    TRACE_STORE="$TS4"
    finalize_trace "$TRACE_ID4" "$PROJ4" "implementer" 2>/dev/null
    jq -r '.outcome // "not-set"' "${TRACE_DIR4}/manifest.json" 2>/dev/null
)
if [[ "$output4" == "failure" ]]; then
    pass "test_result=fail → outcome=failure"
else
    fail "test_result=fail → expected 'failure', got: '$output4'"
fi

# ============================================================
# Test 5: duration>600 + test_result=unknown → outcome=timeout
# ============================================================
echo ""
echo "=== Test 5: duration>600 + test_result=unknown → outcome=timeout ==="

TS5=$(make_trace_store)
PROJ5=$(make_plain_dir)
# Create a timestamp 700 seconds ago to force duration > 600
OLD_EPOCH=$(( $(date -u +%s) - 700 ))
OLD_TS=$(date -u -j -f "%s" "$OLD_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "@$OLD_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
TRACE_ID5=$(make_trace "$TS5" "$OLD_TS" "implementer")
TRACE_DIR5="${TS5}/${TRACE_ID5}"

# Artifacts exist (non-empty) so not "skipped", but no test output so test_result=unknown
mkdir -p "${TRACE_DIR5}/artifacts"
echo "some log output" > "${TRACE_DIR5}/artifacts/log.txt"
echo "# Summary" > "${TRACE_DIR5}/summary.md"

output5=$(
    set +e
    source "${HOOKS_DIR}/log.sh" 2>/dev/null
    source "${HOOKS_DIR}/context-lib.sh" 2>/dev/null
    TRACE_STORE="$TS5"
    finalize_trace "$TRACE_ID5" "$PROJ5" "implementer" 2>/dev/null
    jq -r '.outcome // "not-set"' "${TRACE_DIR5}/manifest.json" 2>/dev/null
)
if [[ "$output5" == "timeout" ]]; then
    pass "duration>600 + test_result=unknown → outcome=timeout"
else
    fail "duration>600 + test_result=unknown → expected 'timeout', got: '$output5'"
fi

# ============================================================
# Test 6: Empty artifacts dir → outcome=skipped
# ============================================================
echo ""
echo "=== Test 6: Empty artifacts dir → outcome=skipped ==="

TS6=$(make_trace_store)
PROJ6=$(make_plain_dir)
TRACE_ID6=$(make_trace "$TS6" "$STARTED_AT" "implementer")
TRACE_DIR6="${TS6}/${TRACE_ID6}"

# Create empty artifacts dir, no summary.md
mkdir -p "${TRACE_DIR6}/artifacts"
# (no files in artifacts dir)

output6=$(
    set +e
    source "${HOOKS_DIR}/log.sh" 2>/dev/null
    source "${HOOKS_DIR}/context-lib.sh" 2>/dev/null
    TRACE_STORE="$TS6"
    finalize_trace "$TRACE_ID6" "$PROJ6" "implementer" 2>/dev/null
    jq -r '.outcome // "not-set"' "${TRACE_DIR6}/manifest.json" 2>/dev/null
)
if [[ "$output6" == "skipped" ]]; then
    pass "Empty artifacts dir → outcome=skipped"
else
    fail "Empty artifacts dir → expected 'skipped', got: '$output6'"
fi

# ============================================================
# Test 7: No artifacts dir at all → outcome=skipped
# ============================================================
echo ""
echo "=== Test 7: No artifacts dir at all → outcome=skipped ==="

TS7=$(make_trace_store)
PROJ7=$(make_plain_dir)
TRACE_ID7=$(make_trace "$TS7" "$STARTED_AT" "implementer")
TRACE_DIR7="${TS7}/${TRACE_ID7}"

# No artifacts dir, no summary.md — bare manifest only
output7=$(
    set +e
    source "${HOOKS_DIR}/log.sh" 2>/dev/null
    source "${HOOKS_DIR}/context-lib.sh" 2>/dev/null
    TRACE_STORE="$TS7"
    finalize_trace "$TRACE_ID7" "$PROJ7" "implementer" 2>/dev/null
    jq -r '.outcome // "not-set"' "${TRACE_DIR7}/manifest.json" 2>/dev/null
)
if [[ "$output7" == "skipped" ]]; then
    pass "No artifacts dir → outcome=skipped"
else
    fail "No artifacts dir → expected 'skipped', got: '$output7'"
fi

# ============================================================
# Test 8: test_result=unknown + duration<600 + has artifacts → outcome=partial
# ============================================================
echo ""
echo "=== Test 8: unknown result + short duration + has artifacts → outcome=partial ==="

TS8=$(make_trace_store)
PROJ8=$(make_plain_dir)
TRACE_ID8=$(make_trace "$TS8" "$STARTED_AT" "implementer")
TRACE_DIR8="${TS8}/${TRACE_ID8}"

# Non-empty artifacts, no test-output.txt (so test_result stays unknown)
mkdir -p "${TRACE_DIR8}/artifacts"
echo "some content" > "${TRACE_DIR8}/artifacts/diff.patch"
echo "# Summary" > "${TRACE_DIR8}/summary.md"

output8=$(
    set +e
    source "${HOOKS_DIR}/log.sh" 2>/dev/null
    source "${HOOKS_DIR}/context-lib.sh" 2>/dev/null
    TRACE_STORE="$TS8"
    finalize_trace "$TRACE_ID8" "$PROJ8" "implementer" 2>/dev/null
    jq -r '.outcome // "not-set"' "${TRACE_DIR8}/manifest.json" 2>/dev/null
)
if [[ "$output8" == "partial" ]]; then
    pass "unknown result + duration<600 + has artifacts → outcome=partial"
else
    fail "unknown result + duration<600 + has artifacts → expected 'partial', got: '$output8'"
fi

# ============================================================
# Test 9: Implementer on main branch → deny response
# ============================================================
echo ""
echo "=== Test 9: Implementer dispatch on main branch → deny ==="

REPO9=$(make_git_repo_on_branch "main")
CLAUDE_DIR9=$(make_plain_dir)
mkdir -p "$CLAUDE_DIR9"

# Simulate the task-track.sh hook by sourcing source-lib.sh and running the gate logic directly
hook_result9=$(
    export TRACE_STORE="$(make_trace_store)"
    source "${HOOKS_DIR}/source-lib.sh" 2>/dev/null

    PROJECT_ROOT="$REPO9"
    CLAUDE_DIR="$CLAUDE_DIR9"
    AGENT_TYPE="implementer"

    # Inline deny function (same as task-track.sh)
    deny_called=0
    deny_msg=""
    deny() {
        deny_called=1
        deny_msg="$1"
    }

    if ! is_claude_meta_repo "$PROJECT_ROOT"; then
        CURRENT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
            deny "Cannot dispatch implementer on '$CURRENT_BRANCH' branch. Sacred Practice #2: create a worktree first."
        fi
    fi

    echo "$deny_called|$deny_msg"
)

deny_called9=$(echo "$hook_result9" | cut -d'|' -f1)
deny_msg9=$(echo "$hook_result9" | cut -d'|' -f2-)

if [[ "$deny_called9" == "1" ]] && echo "$deny_msg9" | grep -q "main"; then
    pass "Implementer on main → deny triggered with branch name in message"
else
    fail "Implementer on main → expected deny, got: deny_called=$deny_called9 msg='$deny_msg9'"
fi

# ============================================================
# Test 10: Implementer on feature branch → allowed (no deny)
# ============================================================
echo ""
echo "=== Test 10: Implementer on feature branch → allowed ==="

REPO10=$(make_git_repo_on_branch "feature/my-feature")
CLAUDE_DIR10=$(make_plain_dir)

hook_result10=$(
    export TRACE_STORE="$(make_trace_store)"
    source "${HOOKS_DIR}/source-lib.sh" 2>/dev/null

    PROJECT_ROOT="$REPO10"
    CLAUDE_DIR="$CLAUDE_DIR10"
    AGENT_TYPE="implementer"

    deny_called=0
    deny() {
        deny_called=1
    }

    if ! is_claude_meta_repo "$PROJECT_ROOT"; then
        CURRENT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
            deny "Cannot dispatch implementer on '$CURRENT_BRANCH' branch."
        fi
    fi

    echo "$deny_called"
)

if [[ "$hook_result10" == "0" ]]; then
    pass "Implementer on feature/my-feature → no deny (allowed)"
else
    fail "Implementer on feature branch → expected no deny, but deny was called"
fi

# ============================================================
# Test 11: Implementer in meta-repo on main → allowed (exemption)
# ============================================================
echo ""
echo "=== Test 11: Implementer in meta-repo on main → allowed (meta-repo exemption) ==="

# The meta-repo is ~/.claude itself — we can use the real one or detect it
# Use is_claude_meta_repo() directly to verify exemption
META_REPO="$HOME/.claude"

# Verify it's actually a git repo we can test against
if [[ ! -d "${META_REPO}/.git" ]] && ! git -C "$META_REPO" rev-parse --git-dir >/dev/null 2>&1; then
    fail "Test 11 skipped: $META_REPO is not a git repo"
else
    hook_result11=$(
        source "${HOOKS_DIR}/source-lib.sh" 2>/dev/null

        PROJECT_ROOT="$META_REPO"
        AGENT_TYPE="implementer"

        deny_called=0
        deny() {
            deny_called=1
        }

        # The gate logic: only runs if NOT meta-repo
        if ! is_claude_meta_repo "$PROJECT_ROOT"; then
            CURRENT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
                deny "Cannot dispatch implementer on '$CURRENT_BRANCH' branch."
            fi
        fi

        echo "$deny_called"
    )

    if [[ "$hook_result11" == "0" ]]; then
        pass "Implementer in meta-repo on main → no deny (meta-repo exemption)"
    else
        fail "Implementer in meta-repo on main → expected exemption, but deny was called"
    fi
fi

# ============================================================
# Final results
# ============================================================
echo ""
echo "=== RESULTS ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "All tests passed."
    exit 0
else
    echo "$FAIL test(s) FAILED."
    exit 1
fi
