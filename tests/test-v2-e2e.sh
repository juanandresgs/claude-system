#!/usr/bin/env bash
# E2E Intent Validation — exercises all 5 v2 intents in isolation.
# Each intent gets its own temp directory. Target: <30s total.
#
# @decision DEC-V2-E2E-001
# @title E2E intent validation for v2 governance system
# @status accepted
# @rationale The v2 system has 5 key intents (trace, recovery, storytelling, steering,
# cross-session learning) that each span multiple functions and hooks. Unit tests
# validate individual functions; this E2E suite validates the intents end-to-end
# using real temp directories and real git repos. One run covers all 5 intents.
# Target runtime: <30s. Each intent is isolated (separate temp dir) so failures
# don't cascade.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/hooks"

source "$HOOKS_DIR/context-lib.sh"

# Test framework
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
passed=0
failed=0
skipped=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; passed=$((passed + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1${2:+ — $2}"; failed=$((failed + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC} $1${2:+ — $2}"; skipped=$((skipped + 1)); }

# Safe cleanup helper — prevents CWD-deletion bug
safe_cleanup() {
    local dir="$1"
    local fallback="${2:-$SCRIPT_DIR}"
    [[ "$(pwd)" == "$dir"* ]] && cd "$fallback"
    rm -rf "$dir"
}

# ============================================================================
# INTENT-01: Every session leaves a trace
# ============================================================================

echo "=== INTENT-01: Every session leaves a trace ==="
I01_DIR=$(mktemp -d)
mkdir -p "$I01_DIR/.claude" "$I01_DIR/.git"

# Write 5 events
append_session_event "session_start" '{"project":"test","branch":"main"}' "$I01_DIR"
append_session_event "write" '{"file":"foo.py"}' "$I01_DIR"
append_session_event "write" '{"file":"bar.py"}' "$I01_DIR"
append_session_event "write" '{"file":"foo.py"}' "$I01_DIR"
append_session_event "gate_eval" '{"hook":"guard","check":"test_gate","result":"block","reason":"tests failing"}' "$I01_DIR"

# Verify: event file exists with valid JSONL
EVENT_FILE="$I01_DIR/.claude/.session-events.jsonl"
[[ -f "$EVENT_FILE" ]] && pass "event file created" || fail "event file missing"

# Verify: correct line count
LINE_COUNT=$(wc -l < "$EVENT_FILE" | tr -d ' ')
[[ "$LINE_COUNT" -eq 5 ]] && pass "5 events written" || fail "expected 5 events, got $LINE_COUNT"

# Verify: each line is valid JSON
VALID_JSON=true
while IFS= read -r line; do
    echo "$line" | jq . > /dev/null 2>&1 || { VALID_JSON=false; break; }
done < "$EVENT_FILE"
[[ "$VALID_JSON" == "true" ]] && pass "all lines valid JSON" || fail "invalid JSON in event file"

# Verify: session archive simulation
# Create session archive directory structure
PROJECT_HASH=$(echo "$I01_DIR" | shasum -a 256 | cut -c1-12)
ARCHIVE_DIR="$I01_DIR/sessions/$PROJECT_HASH"
mkdir -p "$ARCHIVE_DIR"
SESSION_ID="test-session-$(date +%s)"

# Archive the event file (simulating session-end.sh logic)
cp "$EVENT_FILE" "$ARCHIVE_DIR/${SESSION_ID}.jsonl"
rm -f "$EVENT_FILE"

[[ -f "$ARCHIVE_DIR/${SESSION_ID}.jsonl" ]] && pass "session archived" || fail "archive missing"
[[ ! -f "$EVENT_FILE" ]] && pass "event file cleaned up" || fail "event file not cleaned"

# Verify: archived file has valid JSONL
ARCHIVE_LINES=$(wc -l < "$ARCHIVE_DIR/${SESSION_ID}.jsonl" | tr -d ' ')
[[ "$ARCHIVE_LINES" -eq 5 ]] && pass "archive has all events" || fail "archive has $ARCHIVE_LINES events"

safe_cleanup "$I01_DIR" "$SCRIPT_DIR"
echo ""

# ============================================================================
# INTENT-02: Mid-session recovery in seconds
# ============================================================================

echo "=== INTENT-02: Mid-session recovery in seconds ==="
I02_DIR=$(mktemp -d)
cd "$I02_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
git checkout -q -b feature/test-recovery
mkdir -p .claude

# Create initial file and commit
echo "original content" > app.py
git add app.py && git commit -q -m "initial"

# Simulate checkpoint creation (simplified — checkpoint.sh uses git refs)
# Write 6 versions, creating checkpoints via direct git ref creation
for i in $(seq 1 6); do
    echo "version $i" > app.py
    git add app.py
    TREE=$(git write-tree)
    COMMIT=$(git commit-tree "$TREE" -m "checkpoint write $i" -p HEAD)
    git update-ref "refs/checkpoints/auto-$(printf '%03d' $i)" "$COMMIT"
    append_session_event "write" "{\"file\":\"app.py\"}" "$I02_DIR"
done

# Verify: checkpoint refs exist
REF_COUNT=$(git for-each-ref refs/checkpoints/ --format='%(refname)' | wc -l | tr -d ' ')
[[ "$REF_COUNT" -eq 6 ]] && pass "6 checkpoint refs created" || fail "expected 6 refs, got $REF_COUNT"

# Verify: checkpoint commit tree matches
# Sort by refname (auto-001..auto-006) so tail -1 reliably gives the last checkpoint
# (--sort=-committerdate is unreliable when commits are created in the same second)
LAST_CP=$(git for-each-ref refs/checkpoints/ --sort=refname --format='%(objectname)' | tail -1)
[[ -n "$LAST_CP" ]] && pass "latest checkpoint ref found" || fail "no checkpoint ref"

# Break the file
echo "BROKEN CONTENT" > app.py
[[ "$(cat app.py)" == "BROKEN CONTENT" ]] && pass "file broken for recovery test" || fail "break failed"

# Recover from checkpoint
START_TIME=$(date +%s%N 2>/dev/null || date +%s)
git checkout "$LAST_CP" -- app.py 2>/dev/null
END_TIME=$(date +%s%N 2>/dev/null || date +%s)

# Verify: file restored
RECOVERED=$(cat app.py)
[[ "$RECOVERED" == "version 6" ]] && pass "file recovered from checkpoint" || fail "recovery failed: got '$RECOVERED'"

# Measure recovery time (nanoseconds to seconds)
if [[ "$START_TIME" =~ [0-9]{10,} ]]; then
    ELAPSED_NS=$((END_TIME - START_TIME))
    ELAPSED_MS=$((ELAPSED_NS / 1000000))
    [[ "$ELAPSED_MS" -lt 2000 ]] && pass "recovery under 2s (${ELAPSED_MS}ms)" || fail "recovery too slow: ${ELAPSED_MS}ms"
else
    pass "recovery completed (timing not available on this OS)"
fi

cd "$SCRIPT_DIR"
safe_cleanup "$I02_DIR" "$SCRIPT_DIR"
echo ""

# ============================================================================
# INTENT-03: Commits tell engineering stories
# ============================================================================

echo "=== INTENT-03: Commits tell engineering stories ==="
I03_DIR=$(mktemp -d)
mkdir -p "$I03_DIR/.claude" "$I03_DIR/.git"

# Build event log with 10 events of mixed types (>3 for non-trivial)
append_session_event "session_start" '{"project":"test","branch":"feature/auth"}' "$I03_DIR"
append_session_event "write" '{"file":"auth.py"}' "$I03_DIR"
append_session_event "write" '{"file":"auth.py"}' "$I03_DIR"
append_session_event "test_run" '{"result":"fail","failures":2,"assertion":"test_validate_jwt"}' "$I03_DIR"
append_session_event "write" '{"file":"auth.py"}' "$I03_DIR"
append_session_event "test_run" '{"result":"pass","failures":0}' "$I03_DIR"
append_session_event "checkpoint" '{"ref":"refs/checkpoints/auto-001","file":"auth.py","trigger":"n=5"}' "$I03_DIR"
append_session_event "agent_start" '{"type":"implementer"}' "$I03_DIR"
append_session_event "write" '{"file":"test_auth.py"}' "$I03_DIR"
append_session_event "agent_start" '{"type":"tester"}' "$I03_DIR"

# Call get_session_summary_context
SUMMARY=$(get_session_summary_context "$I03_DIR")

# Verify: contains Session Context header (use -F -e — pattern starts with dashes, looks like grep flag)
echo "$SUMMARY" | grep -qF -e '--- Session Context ---' && pass "session context header present" || fail "missing header"

# Verify: Stats line present
echo "$SUMMARY" | grep -q 'Stats:' && pass "Stats line present" || fail "missing Stats"

# Verify: Stats line has correct tool call count (4 writes: auth.py x3, test_auth.py x1)
echo "$SUMMARY" | grep 'Stats:' | grep -q '4 tool calls' && pass "correct tool call count (4)" || fail "wrong tool count in: $(echo "$SUMMARY" | grep 'Stats:')"

# Verify: Checkpoints counted (1 checkpoint event)
echo "$SUMMARY" | grep 'Stats:' | grep -q '1 checkpoints' && pass "checkpoint count correct" || fail "wrong checkpoint count in: $(echo "$SUMMARY" | grep 'Stats:')"

# Verify: Friction line appears (we have test failures)
echo "$SUMMARY" | grep -q 'Friction:' && pass "Friction line present" || fail "missing Friction"
echo "$SUMMARY" | grep 'Friction:' | grep -q 'test_validate_jwt' && pass "top assertion in friction" || fail "assertion not in friction"

# Verify: Agents line
echo "$SUMMARY" | grep -q 'Agents:' && pass "Agents line present" || fail "missing Agents line"
echo "$SUMMARY" | grep 'Agents:' | grep -q 'implementer' && pass "implementer in agents" || fail "implementer not listed"
echo "$SUMMARY" | grep 'Agents:' | grep -q 'tester' && pass "tester in agents" || fail "tester not listed"

# Verify: trivial session returns empty
I03_TRIVIAL=$(mktemp -d)
mkdir -p "$I03_TRIVIAL/.claude" "$I03_TRIVIAL/.git"
append_session_event "session_start" '{"project":"test"}' "$I03_TRIVIAL"
append_session_event "write" '{"file":"x.py"}' "$I03_TRIVIAL"
TRIVIAL_SUMMARY=$(get_session_summary_context "$I03_TRIVIAL")
[[ -z "$TRIVIAL_SUMMARY" ]] && pass "trivial session returns empty" || fail "trivial session non-empty: $TRIVIAL_SUMMARY"

safe_cleanup "$I03_DIR" "$SCRIPT_DIR"
safe_cleanup "$I03_TRIVIAL" "$SCRIPT_DIR"
echo ""

# ============================================================================
# INTENT-04: Hooks steer, not just block
# ============================================================================

echo "=== INTENT-04: Hooks steer, not just block ==="
I04_DIR=$(mktemp -d)
mkdir -p "$I04_DIR/.claude" "$I04_DIR/.git"

# Set up test state: failing tests, 1 gate strike
echo "fail|3|$(date +%s)" > "$I04_DIR/.claude/.test-status"
echo "1|$(date +%s)" > "$I04_DIR/.claude/.test-gate-strikes"

# Write events: edit->fail->edit->fail pattern
append_session_event "write" '{"file":"compute.py"}' "$I04_DIR"
append_session_event "test_run" '{"result":"fail","failures":1,"assertion":"test_compute_result"}' "$I04_DIR"
append_session_event "write" '{"file":"compute.py"}' "$I04_DIR"
append_session_event "test_run" '{"result":"fail","failures":1,"assertion":"test_compute_result"}' "$I04_DIR"

# Run detect_approach_pivots
# Wrap in set +e since internal grep pipelines can exit 1 on no-match under pipefail
set +e
detect_approach_pivots "$I04_DIR"
set -e

# Verify: pivots detected
[[ "$PIVOT_COUNT" -gt 0 ]] && pass "pivot detected (count=$PIVOT_COUNT)" || fail "no pivots detected"
echo "$PIVOT_FILES" | grep -q "compute.py" && pass "compute.py identified as pivot file" || fail "compute.py not in pivots: $PIVOT_FILES"
echo "$PIVOT_ASSERTIONS" | grep -q "test_compute_result" && pass "test_compute_result in assertions" || fail "assertion not found: $PIVOT_ASSERTIONS"

# Verify: trajectory has the right counts
# get_session_trajectory uses grep pipelines that exit 1 on no-match (e.g. no "block" events).
# With set -o pipefail those propagate — disable set -e around the call, re-enable after.
set +e
get_session_trajectory "$I04_DIR"
set -e
[[ "$TRAJ_TEST_FAILURES" -eq 2 ]] && pass "2 test failures counted" || fail "expected 2 failures, got $TRAJ_TEST_FAILURES"
[[ "$TRAJ_TOOL_CALLS" -eq 2 ]] && pass "2 write events counted" || fail "expected 2 writes, got $TRAJ_TOOL_CALLS"

# Compare: scenario without event log (generic message)
I04_GENERIC=$(mktemp -d)
mkdir -p "$I04_GENERIC/.claude" "$I04_GENERIC/.git"
echo "fail|3|$(date +%s)" > "$I04_GENERIC/.claude/.test-status"
set +e
detect_approach_pivots "$I04_GENERIC"
set -e
[[ "$PIVOT_COUNT" -eq 0 ]] && pass "no pivots without event log (generic fallback)" || fail "unexpected pivots without events"

safe_cleanup "$I04_DIR" "$SCRIPT_DIR"
safe_cleanup "$I04_GENERIC" "$SCRIPT_DIR"
echo ""

# ============================================================================
# INTENT-05: Cross-session learning
# ============================================================================

echo "=== INTENT-05: Cross-session learning ==="
I05_DIR=$(mktemp -d)
mkdir -p "$I05_DIR/.git"

# Create session archive with 4 synthetic entries
PROJECT_HASH=$(echo "$I05_DIR" | shasum -a 256 | cut -c1-12)
SESSION_DIR="$HOME/.claude/sessions/$PROJECT_HASH"
mkdir -p "$SESSION_DIR"

# Write 4 index entries — 2 have friction "test_auth_token", 1 has unique friction
cat > "$SESSION_DIR/index.jsonl" << 'ENTRIES'
{"id":"s1","started":"2026-02-14T10:00:00Z","duration_min":15,"outcome":"pass","files_touched":["auth.py","test_auth.py"],"friction":["test_auth_token"]}
{"id":"s2","started":"2026-02-15T10:00:00Z","duration_min":22,"outcome":"fail","files_touched":["auth.py"],"friction":["test_auth_token","test_session_expiry"]}
{"id":"s3","started":"2026-02-16T10:00:00Z","duration_min":8,"outcome":"pass","files_touched":["api.py"],"friction":[]}
{"id":"s4","started":"2026-02-17T10:00:00Z","duration_min":30,"outcome":"pass","files_touched":["compute.py","test_compute.py"],"friction":["test_compute_accuracy"]}
ENTRIES

# Call get_prior_sessions
PRIOR=$(get_prior_sessions "$I05_DIR")

# Verify: "Prior sessions" header present
echo "$PRIOR" | grep -q 'Prior sessions' && pass "prior sessions header present" || fail "missing header"

# Verify: recent summaries shown (at least the last 3 session dates)
echo "$PRIOR" | grep -q '2026-02-15' && pass "session 2 in output" || fail "session 2 missing"
echo "$PRIOR" | grep -q '2026-02-16' && pass "session 3 in output" || fail "session 3 missing"
echo "$PRIOR" | grep -q '2026-02-17' && pass "session 4 in output" || fail "session 4 missing"

# Verify: "Recurring friction" section present with test_auth_token
echo "$PRIOR" | grep -q 'Recurring friction' && pass "recurring friction header present" || fail "missing recurring friction"
echo "$PRIOR" | grep -q 'test_auth_token' && pass "test_auth_token in recurring friction" || fail "test_auth_token missing"

# Verify: unique friction NOT flagged as recurring
if echo "$PRIOR" | grep -q 'test_compute_accuracy'; then
    fail "unique friction falsely flagged as recurring"
else
    pass "unique friction correctly excluded"
fi

# Verify: threshold check — fewer than 3 sessions returns empty
SPARSE_DIR=$(mktemp -d)
mkdir -p "$SPARSE_DIR/.git"
SPARSE_HASH=$(echo "$SPARSE_DIR" | shasum -a 256 | cut -c1-12)
SPARSE_SESSION_DIR="$HOME/.claude/sessions/$SPARSE_HASH"
mkdir -p "$SPARSE_SESSION_DIR"
echo '{"id":"s1","started":"2026-02-14T10:00:00Z","duration_min":5,"outcome":"pass","files_touched":[],"friction":[]}' > "$SPARSE_SESSION_DIR/index.jsonl"
echo '{"id":"s2","started":"2026-02-15T10:00:00Z","duration_min":5,"outcome":"pass","files_touched":[],"friction":[]}' >> "$SPARSE_SESSION_DIR/index.jsonl"
SPARSE_RESULT=$(get_prior_sessions "$SPARSE_DIR")
[[ -z "$SPARSE_RESULT" ]] && pass "fewer than 3 sessions returns empty" || fail "sparse sessions not empty"

# Clean up session archive dirs
safe_cleanup "$I05_DIR" "$SCRIPT_DIR"
safe_cleanup "$SPARSE_DIR" "$SCRIPT_DIR"
rm -rf "$SESSION_DIR" "$SPARSE_SESSION_DIR"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo "==========================="
total=$((passed + failed + skipped))
echo -e "Total: $total | ${GREEN}Passed: $passed${NC} | ${RED}Failed: $failed${NC} | ${YELLOW}Skipped: $skipped${NC}"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
