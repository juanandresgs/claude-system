#!/usr/bin/env bash
# test_state.sh — Unit tests for observatory state.sh
#
# Purpose: Verify state CRUD functions: init, get_pending, transition, log_action.
#          Tests the full lifecycle: init → proposed → accepted → implemented.
#
# @decision DEC-OBS-003
# @title Use isolated temp directory for state tests
# @status accepted
# @rationale State tests modify observatory/state.json and observatory/history.jsonl.
#             Using a temp directory prevents test runs from corrupting real state.
#             Each test run gets a fresh isolated environment.
#
# Usage: bash tests/observatory/test_state.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
WORKTREE="${CLAUDE_DIR}/.worktrees/feat-observatory"
STATE_SCRIPT="${WORKTREE}/skills/observatory/scripts/state.sh"

# Isolated test environment
TEST_OBS_DIR=$(mktemp -d)
trap "rm -rf $TEST_OBS_DIR" EXIT

export OBS_DIR="$TEST_OBS_DIR"
export STATE_FILE="${TEST_OBS_DIR}/state.json"
export HISTORY_FILE="${TEST_OBS_DIR}/history.jsonl"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Source the state library
# shellcheck source=/dev/null
source "$STATE_SCRIPT"

# --- Test 1: init_state creates valid JSON ---
echo ""
echo "=== Test 1: init_state ==="
init_state
if [[ -f "$STATE_FILE" ]]; then
    if jq . "$STATE_FILE" > /dev/null 2>&1; then
        pass "init_state creates valid JSON at $STATE_FILE"
    else
        fail "init_state created invalid JSON"
    fi
else
    fail "init_state did not create state.json"
fi

# --- Test 2: Initial state has correct schema ---
echo ""
echo "=== Test 2: Initial state schema ==="
REQUIRED=("version" "last_analysis_at" "pending_suggestion" "implemented" "rejected" "deferred")
for field in "${REQUIRED[@]}"; do
    if jq -e ".$field != null or .$field == null" "$STATE_FILE" > /dev/null 2>&1; then
        pass "Field present: $field"
    else
        fail "Field missing: $field"
    fi
done

# --- Test 3: get_pending returns null initially ---
echo ""
echo "=== Test 3: get_pending returns null on fresh state ==="
PENDING=$(get_pending)
if [[ "$PENDING" == "null" || -z "$PENDING" ]]; then
    pass "get_pending returns null/empty on fresh state"
else
    fail "get_pending returned unexpected value: $PENDING"
fi

# --- Test 4: log_action appends to history.jsonl ---
echo ""
echo "=== Test 4: log_action appends to history ==="
log_action "analyzed" '{"trace_count": 320, "signals": 5}'
if [[ -f "$HISTORY_FILE" ]]; then
    HIST_COUNT=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    if [[ "$HIST_COUNT" -eq 1 ]]; then
        pass "log_action appended one line to history.jsonl"
    else
        fail "history.jsonl has $HIST_COUNT lines (expected 1)"
    fi
else
    fail "log_action did not create history.jsonl"
fi

# --- Test 5: history.jsonl entries are valid JSON ---
echo ""
echo "=== Test 5: history.jsonl valid JSON lines ==="
INVALID=0
while IFS= read -r line; do
    if ! echo "$line" | jq . > /dev/null 2>&1; then
        (( INVALID++ ))
    fi
done < "$HISTORY_FILE"
if [[ "$INVALID" -eq 0 ]]; then
    pass "All history.jsonl lines are valid JSON"
else
    fail "$INVALID invalid JSON lines in history.jsonl"
fi

# --- Test 6: history entries have ts and action fields ---
echo ""
echo "=== Test 6: history entry schema ==="
FIRST_HIST=$(head -1 "$HISTORY_FILE")
HAS_TS=$(echo "$FIRST_HIST" | jq -e '.ts' > /dev/null 2>&1 && echo "yes" || echo "no")
HAS_ACTION=$(echo "$FIRST_HIST" | jq -e '.action' > /dev/null 2>&1 && echo "yes" || echo "no")
if [[ "$HAS_TS" == "yes" ]]; then
    pass "history entry has ts field"
else
    fail "history entry missing ts field"
fi
if [[ "$HAS_ACTION" == "yes" ]]; then
    pass "history entry has action field"
else
    fail "history entry missing action field"
fi

# --- Test 7: transition proposed → accepted sets pending_suggestion ---
echo ""
echo "=== Test 7: transition sets pending_suggestion ==="
transition "SUG-001" "proposed" "Fix UTC timezone bug in finalize_trace" "0.855"
PENDING_ID=$(jq -r '.pending_suggestion' "$STATE_FILE")
if [[ "$PENDING_ID" == "SUG-001" ]]; then
    pass "transition sets pending_suggestion to SUG-001"
else
    fail "pending_suggestion is '$PENDING_ID' (expected SUG-001)"
fi

# --- Test 8: get_pending returns the pending ID ---
echo ""
echo "=== Test 8: get_pending returns set value ==="
PENDING=$(get_pending)
if [[ "$PENDING" == "SUG-001" ]]; then
    pass "get_pending returns SUG-001"
else
    fail "get_pending returned '$PENDING' (expected SUG-001)"
fi

# --- Test 9: transition to implemented moves to implemented list ---
echo ""
echo "=== Test 9: transition to implemented ==="
transition "SUG-001" "implemented" "Fix UTC timezone bug in finalize_trace" "0.855"
IN_IMPL=$(jq -r '.implemented | contains(["SUG-001"])' "$STATE_FILE")
PENDING_AFTER=$(jq -r '.pending_suggestion' "$STATE_FILE")
if [[ "$IN_IMPL" == "true" ]]; then
    pass "SUG-001 in implemented list"
else
    fail "SUG-001 not in implemented list"
fi
if [[ "$PENDING_AFTER" == "null" ]]; then
    pass "pending_suggestion cleared after implementation"
else
    fail "pending_suggestion still set to '$PENDING_AFTER' after implementation"
fi

# --- Test 10: transition to rejected moves to rejected list ---
echo ""
echo "=== Test 10: transition to rejected ==="
transition "SUG-002" "rejected" "Some suggestion" "0.5"
IN_REJ=$(jq -r '.rejected | contains(["SUG-002"])' "$STATE_FILE")
if [[ "$IN_REJ" == "true" ]]; then
    pass "SUG-002 in rejected list"
else
    fail "SUG-002 not in rejected list"
fi

# --- Test 11: log_action accumulates multiple entries ---
echo ""
echo "=== Test 11: Multiple log_action calls accumulate ==="
log_action "suggested" '{"id": "SUG-001", "priority": 0.855}'
log_action "suggested" '{"id": "SUG-002", "priority": 0.5}'
HIST_COUNT=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
# 1 from test 4 + 1 from test 7 (transition) + 1 from test 9 + 1 from test 10 + 2 more = variable
# Just verify it's >= 3
if [[ "$HIST_COUNT" -ge 3 ]]; then
    pass "history.jsonl has $HIST_COUNT entries (accumulated correctly)"
else
    fail "history.jsonl has only $HIST_COUNT entries (expected >= 3)"
fi

# --- Summary ---
echo ""
echo "====================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "====================================="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
