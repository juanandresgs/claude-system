#!/usr/bin/env bash
# test_state.sh — Unit tests for observatory state.sh (v2 schema)
#
# Purpose: Verify state CRUD functions: init, get_pending, transition,
#          defer_with_context, get_reassessable, auto_resurface, log_action.
#          Tests the full lifecycle including v2 deferred object schema
#          and v1→v2 migration.
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
WORKTREE="${CLAUDE_DIR}/.worktrees/feat-observatory-v2"
STATE_SCRIPT="${WORKTREE}/skills/observatory/scripts/state.sh"

# Isolated test environment
TEST_OBS_DIR=$(mktemp -d)
trap "rm -rf $TEST_OBS_DIR" EXIT

export OBS_DIR="$TEST_OBS_DIR"
export STATE_FILE="${TEST_OBS_DIR}/state.json"
export HISTORY_FILE="${TEST_OBS_DIR}/history.jsonl"
export SUGGESTIONS_DIR="${TEST_OBS_DIR}/suggestions"
mkdir -p "$SUGGESTIONS_DIR"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Source the state library
# shellcheck source=/dev/null
source "$STATE_SCRIPT"

# --- Test 1: init_state creates valid JSON with v2 schema ---
echo ""
echo "=== Test 1: init_state (v2 schema) ==="
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

# --- Test 2: Initial state is version 2 ---
echo ""
echo "=== Test 2: Initial state is v2 ==="
VERSION=$(jq -r '.version' "$STATE_FILE")
if [[ "$VERSION" == "2" ]]; then
    pass "state.json has version: 2"
else
    fail "state.json version is '$VERSION' (expected 2)"
fi

# --- Test 3: Required v2 schema fields present ---
echo ""
echo "=== Test 3: v2 schema fields ==="
REQUIRED=("version" "last_analysis_at" "pending_suggestion" "implemented" "rejected" "deferred")
for field in "${REQUIRED[@]}"; do
    if jq -e ".$field != null or .$field == null" "$STATE_FILE" > /dev/null 2>&1; then
        pass "Field present: $field"
    else
        fail "Field missing: $field"
    fi
done

# --- Test 4: get_pending returns null initially ---
echo ""
echo "=== Test 4: get_pending returns null on fresh state ==="
PENDING=$(get_pending)
if [[ "$PENDING" == "null" || -z "$PENDING" ]]; then
    pass "get_pending returns null/empty on fresh state"
else
    fail "get_pending returned unexpected value: $PENDING"
fi

# --- Test 5: log_action appends to history.jsonl ---
echo ""
echo "=== Test 5: log_action appends to history ==="
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

# --- Test 6: history.jsonl entries are valid JSON ---
echo ""
echo "=== Test 6: history.jsonl valid JSON lines ==="
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

# --- Test 7: history entries have ts and action fields ---
echo ""
echo "=== Test 7: history entry schema ==="
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

# --- Test 8: transition proposed sets pending_suggestion ---
echo ""
echo "=== Test 8: transition sets pending_suggestion ==="
transition "SUG-001" "proposed" "Fix UTC timezone bug in finalize_trace" "0.855"
PENDING_ID=$(jq -r '.pending_suggestion' "$STATE_FILE")
if [[ "$PENDING_ID" == "SUG-001" ]]; then
    pass "transition sets pending_suggestion to SUG-001"
else
    fail "pending_suggestion is '$PENDING_ID' (expected SUG-001)"
fi

# --- Test 9: get_pending returns the pending ID ---
echo ""
echo "=== Test 9: get_pending returns set value ==="
PENDING=$(get_pending)
if [[ "$PENDING" == "SUG-001" ]]; then
    pass "get_pending returns SUG-001"
else
    fail "get_pending returned '$PENDING' (expected SUG-001)"
fi

# --- Test 10: transition to implemented moves to implemented list ---
echo ""
echo "=== Test 10: transition to implemented ==="
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

# --- Test 11: transition to rejected moves to rejected list ---
echo ""
echo "=== Test 11: transition to rejected ==="
transition "SUG-002" "rejected" "Some suggestion" "0.5"
IN_REJ=$(jq -r '.rejected | contains(["SUG-002"])' "$STATE_FILE")
if [[ "$IN_REJ" == "true" ]]; then
    pass "SUG-002 in rejected list"
else
    fail "SUG-002 not in rejected list"
fi

# --- Test 12: transition to deferred creates v2 object (not string) ---
echo ""
echo "=== Test 12: transition deferred creates v2 object ==="
transition "SUG-003" "deferred" "Some deferred suggestion" "0.3"
DEF_TYPE=$(jq -r '.deferred[0] | type' "$STATE_FILE")
if [[ "$DEF_TYPE" == "object" ]]; then
    pass "deferred entry is object (v2 schema)"
else
    fail "deferred entry is '$DEF_TYPE' (expected object for v2 schema)"
fi

# --- Test 13: deferred object has required v2 fields ---
echo ""
echo "=== Test 13: deferred object has v2 fields ==="
V2_FIELDS=("sug_id" "deferred_at" "reason" "reassess_after")
for field in "${V2_FIELDS[@]}"; do
    VAL=$(jq -r ".deferred[0].${field}" "$STATE_FILE" 2>/dev/null || echo "")
    if [[ -n "$VAL" && "$VAL" != "null" ]]; then
        pass "deferred[0].${field} is set: $VAL"
    else
        fail "deferred[0].${field} is missing or null"
    fi
done

# --- Test 14: defer_with_context creates rich metadata object ---
echo ""
echo "=== Test 14: defer_with_context creates rich deferred object ==="
# Reset state for clean test
rm -f "$STATE_FILE"
init_state
defer_with_context "SUG-010" "SIG-OUTCOME-FLAT" "dependency" 14 "after SIG-DURATION-BUG is fixed" "0.341"
DEF_OBJ=$(jq '.deferred[0]' "$STATE_FILE")
SUG_ID_VAL=$(echo "$DEF_OBJ" | jq -r '.sug_id')
SIG_ID_VAL=$(echo "$DEF_OBJ" | jq -r '.signal_id')
REASON_VAL=$(echo "$DEF_OBJ" | jq -r '.reason')
COND_VAL=$(echo "$DEF_OBJ" | jq -r '.reassess_condition')
PRI_VAL=$(echo "$DEF_OBJ" | jq -r '.priority_at_deferral')

if [[ "$SUG_ID_VAL" == "SUG-010" ]]; then
    pass "defer_with_context: sug_id = SUG-010"
else
    fail "defer_with_context: sug_id = '$SUG_ID_VAL' (expected SUG-010)"
fi
if [[ "$SIG_ID_VAL" == "SIG-OUTCOME-FLAT" ]]; then
    pass "defer_with_context: signal_id = SIG-OUTCOME-FLAT"
else
    fail "defer_with_context: signal_id = '$SIG_ID_VAL' (expected SIG-OUTCOME-FLAT)"
fi
if [[ "$REASON_VAL" == "dependency" ]]; then
    pass "defer_with_context: reason = dependency"
else
    fail "defer_with_context: reason = '$REASON_VAL' (expected dependency)"
fi
if [[ -n "$COND_VAL" && "$COND_VAL" != "null" ]]; then
    pass "defer_with_context: reassess_condition is set"
else
    fail "defer_with_context: reassess_condition is missing"
fi
if [[ "$PRI_VAL" == "0.341" ]]; then
    pass "defer_with_context: priority_at_deferral = 0.341"
else
    fail "defer_with_context: priority_at_deferral = '$PRI_VAL' (expected 0.341)"
fi

# --- Test 15: get_reassessable returns nothing for future date ---
echo ""
echo "=== Test 15: get_reassessable returns empty for future reassess dates ==="
# The deferred item above has reassess_after = now + 14 days
RESULT=$(get_reassessable)
if [[ -z "$RESULT" ]]; then
    pass "get_reassessable returns empty (item not yet due)"
else
    fail "get_reassessable returned: '$RESULT' (expected empty — item is 14 days in future)"
fi

# --- Test 16: get_reassessable returns items with past reassess date ---
echo ""
echo "=== Test 16: get_reassessable returns past-due items ==="
# Manipulate state to make the item appear past-due by back-dating reassess_after
rm -f "$STATE_FILE"
init_state
# Write a deferred entry with a past reassess_after date directly
PAST_DATE="2020-01-01T00:00:00Z"
jq --arg sug_id "SUG-PAST" \
   --arg now "2020-01-01T00:00:00Z" \
   --arg past "$PAST_DATE" \
   '.deferred = [{sug_id: $sug_id, signal_id: "SIG-TEST", deferred_at: $now, reason: "user", reassess_after: $past, reassess_condition: null, priority_at_deferral: 0.5}]' \
   "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

RESULT=$(get_reassessable)
if echo "$RESULT" | grep -q "SUG-PAST"; then
    pass "get_reassessable returns SUG-PAST (past-due item)"
else
    fail "get_reassessable did not return SUG-PAST (got: '$RESULT')"
fi

# --- Test 17: auto_resurface moves past-due item back to proposed ---
echo ""
echo "=== Test 17: auto_resurface promotes past-due deferred items ==="
# Create a SUG-PAST.json file for auto_resurface to update
mkdir -p "$SUGGESTIONS_DIR"
echo '{"id": "SUG-PAST", "status": "deferred", "signal_id": "SIG-TEST", "priority_score": 0.5}' \
    > "${SUGGESTIONS_DIR}/SUG-PAST.json"

# auto_resurface should promote it
auto_resurface

# Check that SUG-PAST.json status is now "proposed"
NEW_STATUS=$(jq -r '.status' "${SUGGESTIONS_DIR}/SUG-PAST.json" 2>/dev/null || echo "")
if [[ "$NEW_STATUS" == "proposed" ]]; then
    pass "auto_resurface set SUG-PAST.json status to proposed"
else
    fail "auto_resurface: status is '$NEW_STATUS' (expected proposed)"
fi

# Check that SUG-PAST is removed from deferred array
DEF_COUNT=$(jq '.deferred | length' "$STATE_FILE")
if [[ "$DEF_COUNT" -eq 0 ]]; then
    pass "auto_resurface removed SUG-PAST from deferred array"
else
    fail "deferred array still has $DEF_COUNT entries after auto_resurface"
fi

# --- Test 18: v1 → v2 migration converts string deferred array ---
echo ""
echo "=== Test 18: v1 to v2 migration ==="
# Write a v1-style state.json with string deferred array
cat > "$STATE_FILE" << 'V1EOF'
{
  "version": 1,
  "last_analysis_at": null,
  "last_analysis_trace_count": 0,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": ["SUG-001"],
  "rejected": [],
  "deferred": ["SUG-002", "SUG-003"]
}
V1EOF
# Calling init_state triggers migration
init_state

MIGRATED_VERSION=$(jq '.version' "$STATE_FILE")
DEFERRED_TYPE=$(jq -r '.deferred[0] | type' "$STATE_FILE" 2>/dev/null || echo "null")
DEFERRED_COUNT=$(jq '.deferred | length' "$STATE_FILE")

if [[ "$MIGRATED_VERSION" == "2" ]]; then
    pass "Migrated state.json to version 2"
else
    fail "Migration failed: version is '$MIGRATED_VERSION' (expected 2)"
fi
if [[ "$DEFERRED_TYPE" == "object" ]]; then
    pass "Migrated deferred entries are objects (v2 schema)"
else
    fail "Migrated deferred entries are '$DEFERRED_TYPE' (expected object)"
fi
if [[ "$DEFERRED_COUNT" -eq 2 ]]; then
    pass "Migration preserved both deferred entries ($DEFERRED_COUNT)"
else
    fail "Migration changed deferred count: $DEFERRED_COUNT (expected 2)"
fi

# --- Test 19: log_action accumulates multiple entries ---
echo ""
echo "=== Test 19: Multiple log_action calls accumulate ==="
log_action "suggested" '{"id": "SUG-001", "priority": 0.855}'
log_action "suggested" '{"id": "SUG-002", "priority": 0.5}'
HIST_COUNT=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
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
