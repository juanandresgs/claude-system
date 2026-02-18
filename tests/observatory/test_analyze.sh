#!/usr/bin/env bash
# test_analyze.sh — Unit tests for observatory analyze.sh
#
# Purpose: Verify analyze.sh produces valid analysis-cache.json with correct
#          schema, signal detection, stats, trends, and agent breakdown from
#          real trace index data.
#
# @decision DEC-OBS-001
# @title Test against real trace data (no mocks)
# @status accepted
# @rationale Sacred Practice #5 — test against real implementations. The 360+
#             real trace entries are the ground truth for signal detection.
#             Mocking would obscure the actual data quality issues we're measuring.
#
# Usage: bash tests/observatory/test_analyze.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
WORKTREE="${CLAUDE_DIR}/.worktrees/feat-observatory-v2"
ANALYZE_SCRIPT="${WORKTREE}/skills/observatory/scripts/analyze.sh"
TRACE_INDEX="${CLAUDE_DIR}/traces/index.jsonl"
CACHE_FILE="${WORKTREE}/observatory/analysis-cache.json"
PREV_CACHE_FILE="${WORKTREE}/observatory/analysis-cache.prev.json"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Setup ---
# Point analyze.sh at the worktree's observatory dir (not main repo)
export WORKTREE_DIR="$WORKTREE"
export OBS_DIR="${WORKTREE}/observatory"
export STATE_FILE="${WORKTREE}/observatory/state.json"
mkdir -p "$OBS_DIR"

# Ensure we have a trace index to work with
if [[ ! -f "$TRACE_INDEX" ]]; then
    echo "ERROR: Trace index not found at $TRACE_INDEX — cannot run tests against real data"
    exit 1
fi

TRACE_COUNT=$(wc -l < "$TRACE_INDEX" | tr -d ' ')
echo "Running tests against $TRACE_COUNT real trace entries"

# Clean previous caches for a fresh run
rm -f "$CACHE_FILE" "$PREV_CACHE_FILE"

# --- Test 1: analyze.sh runs without error ---
echo ""
echo "=== Test 1: analyze.sh execution ==="
if bash "$ANALYZE_SCRIPT" 2>&1; then
    pass "analyze.sh exits 0"
else
    fail "analyze.sh exited non-zero"
fi

# --- Test 2: Output file exists ---
echo ""
echo "=== Test 2: Output file creation ==="
if [[ -f "$CACHE_FILE" ]]; then
    pass "analysis-cache.json created"
else
    fail "analysis-cache.json not found at $CACHE_FILE"
fi

# Bail out if no output file — remaining tests can't run
if [[ ! -f "$CACHE_FILE" ]]; then
    echo ""
    echo "RESULTS: $PASS passed, $FAIL failed (aborted — no output file)"
    exit 1
fi

# --- Test 3: Valid JSON ---
echo ""
echo "=== Test 3: Valid JSON output ==="
if jq . "$CACHE_FILE" > /dev/null 2>&1; then
    pass "Valid JSON"
else
    fail "Invalid JSON in analysis-cache.json"
fi

# --- Test 4: Schema fields present (v2 includes trends and agent_breakdown) ---
echo ""
echo "=== Test 4: Required schema fields (v2) ==="
REQUIRED_FIELDS=("version" "generated_at" "trace_stats" "artifact_health" "self_metrics" "improvement_signals" "trends" "agent_breakdown")
for field in "${REQUIRED_FIELDS[@]}"; do
    if jq -e "has(\"$field\")" "$CACHE_FILE" > /dev/null 2>&1; then
        pass "Field present: $field"
    else
        fail "Field missing: $field"
    fi
done

# --- Test 5: trace_stats totals match real data ---
echo ""
echo "=== Test 5: trace_stats.total matches index.jsonl line count ==="
TOTAL_IN_CACHE=$(jq -r '.trace_stats.total' "$CACHE_FILE")
if [[ "$TOTAL_IN_CACHE" -eq "$TRACE_COUNT" ]]; then
    pass "trace_stats.total ($TOTAL_IN_CACHE) matches index.jsonl ($TRACE_COUNT)"
else
    fail "trace_stats.total ($TOTAL_IN_CACHE) != index.jsonl lines ($TRACE_COUNT)"
fi

# --- Test 6: outcome_dist sums to total ---
echo ""
echo "=== Test 6: outcome_dist sums to total ==="
OUTCOME_SUM=$(jq '[.trace_stats.outcome_dist | to_entries[].value] | add // 0' "$CACHE_FILE")
TOTAL=$(jq '.trace_stats.total' "$CACHE_FILE")
if [[ "$OUTCOME_SUM" -eq "$TOTAL" ]]; then
    pass "outcome_dist sums to $TOTAL"
else
    fail "outcome_dist sum ($OUTCOME_SUM) != total ($TOTAL)"
fi

# --- Test 7: improvement_signals is an array ---
echo ""
echo "=== Test 7: improvement_signals structure ==="
if jq -e '.improvement_signals | type == "array"' "$CACHE_FILE" > /dev/null 2>&1; then
    SIG_COUNT=$(jq '.improvement_signals | length' "$CACHE_FILE")
    pass "improvement_signals is array with $SIG_COUNT entries"
else
    fail "improvement_signals is not an array"
fi

# --- Test 8: Each signal has required fields ---
echo ""
echo "=== Test 8: Signal schema ==="
SIG_COUNT=$(jq '.improvement_signals | length' "$CACHE_FILE")
if [[ "$SIG_COUNT" -gt 0 ]]; then
    MISSING_FIELDS=$(jq -r '.improvement_signals[] | select(.id == null or .category == null or .severity == null or .description == null or .evidence == null) | .id // "unknown"' "$CACHE_FILE")
    if [[ -z "$MISSING_FIELDS" ]]; then
        pass "All $SIG_COUNT signals have required fields (id, category, severity, description, evidence)"
    else
        fail "Signals missing required fields: $MISSING_FIELDS"
    fi
else
    pass "No signals to validate (clean system)"
fi

# --- Test 9: SIG-DURATION-BUG detected when data quality issues exist ---
echo ""
echo "=== Test 9: SIG-DURATION-BUG detection ==="
ZERO_COUNT=$(jq -sc '[.[] | select(.duration_seconds == 0)] | length' "$TRACE_INDEX" 2>/dev/null || echo "0")
NEG_COUNT=$(jq -sc '[.[] | select(.duration_seconds < 0)] | length' "$TRACE_INDEX" 2>/dev/null || echo "0")
BAD_DUR=$((ZERO_COUNT + NEG_COUNT))
DURATION_SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-DURATION-BUG") | .id' "$CACHE_FILE" 2>/dev/null || echo "")
if [[ "$BAD_DUR" -gt 0 ]]; then
    if [[ -n "$DURATION_SIG" ]]; then
        pass "SIG-DURATION-BUG detected ($BAD_DUR affected traces)"
    else
        fail "SIG-DURATION-BUG not detected despite $BAD_DUR bad durations"
    fi
else
    pass "No bad durations in index — SIG-DURATION-BUG correctly absent"
fi

# --- Test 10: artifact_health has completeness map ---
echo ""
echo "=== Test 10: artifact_health.completeness ==="
EXPECTED_ARTIFACTS=("summary.md" "test-output.txt" "diff.patch" "files-changed.txt")
for art in "${EXPECTED_ARTIFACTS[@]}"; do
    if jq -e ".artifact_health.completeness[\"$art\"]" "$CACHE_FILE" > /dev/null 2>&1; then
        RATE=$(jq ".artifact_health.completeness[\"$art\"]" "$CACHE_FILE")
        pass "artifact_health.completeness[\"$art\"] = $RATE"
    else
        fail "artifact_health.completeness[\"$art\"] missing"
    fi
done

# --- Test 11: Performance — runs in under 5 seconds ---
echo ""
echo "=== Test 11: Performance ==="
rm -f "$CACHE_FILE"
START=$(date +%s)
bash "$ANALYZE_SCRIPT" > /dev/null 2>&1
END=$(date +%s)
ELAPSED=$(( END - START ))
if [[ "$ELAPSED" -lt 5 ]]; then
    pass "Completed in ${ELAPSED}s (target <5s)"
else
    fail "Took ${ELAPSED}s — exceeds 5s target"
fi

# --- Test 12: Trends field is null on first run (no prev cache) ---
echo ""
echo "=== Test 12: trends is null on first run (no prev cache) ==="
rm -f "$CACHE_FILE" "$PREV_CACHE_FILE"
bash "$ANALYZE_SCRIPT" > /dev/null 2>&1
TRENDS_VAL=$(jq '.trends' "$CACHE_FILE")
if [[ "$TRENDS_VAL" == "null" ]]; then
    pass "trends is null on first run (no analysis-cache.prev.json)"
else
    fail "trends should be null on first run, got: $TRENDS_VAL"
fi

# --- Test 13: Second run produces trends with prev snapshot ---
echo ""
echo "=== Test 13: Second run produces non-null trends ==="
# Run twice — second run should see prev cache
bash "$ANALYZE_SCRIPT" > /dev/null 2>&1
TRENDS_TYPE=$(jq '.trends | type' "$CACHE_FILE")
if [[ "$TRENDS_TYPE" == '"object"' ]]; then
    TREND_DIR=$(jq -r '.trends.signal_trend' "$CACHE_FILE")
    TRACE_DELTA=$(jq '.trends.trace_count_delta' "$CACHE_FILE")
    pass "trends is object after second run (trend: $TREND_DIR, trace_delta: $TRACE_DELTA)"
else
    fail "trends should be object on second run, got type: $TRENDS_TYPE"
fi

# --- Test 14: trends.signal_trend is one of the valid values ---
echo ""
echo "=== Test 14: trends.signal_trend is valid ==="
TREND_VAL=$(jq -r '.trends.signal_trend // "null"' "$CACHE_FILE")
case "$TREND_VAL" in
    improving|worsening|stable)
        pass "trends.signal_trend is valid: $TREND_VAL"
        ;;
    *)
        fail "trends.signal_trend has unexpected value: $TREND_VAL"
        ;;
esac

# --- Test 15: agent_breakdown is an array ---
echo ""
echo "=== Test 15: agent_breakdown structure ==="
if jq -e '.agent_breakdown | type == "array"' "$CACHE_FILE" > /dev/null 2>&1; then
    AGENT_COUNT=$(jq '.agent_breakdown | length' "$CACHE_FILE")
    pass "agent_breakdown is array with $AGENT_COUNT agent types"
else
    fail "agent_breakdown is not an array"
fi

# --- Test 16: agent_breakdown entries have required fields ---
echo ""
echo "=== Test 16: agent_breakdown entry schema ==="
AGENT_COUNT=$(jq '.agent_breakdown | length' "$CACHE_FILE")
if [[ "$AGENT_COUNT" -gt 0 ]]; then
    MISSING=$(jq -r '.agent_breakdown[] | select(.agent_type == null or .count == null) | .agent_type // "unknown"' "$CACHE_FILE")
    if [[ -z "$MISSING" ]]; then
        pass "All $AGENT_COUNT agent_breakdown entries have agent_type and count"
    else
        fail "agent_breakdown entries missing fields: $MISSING"
    fi
else
    pass "No agent_breakdown entries (no agent_type in trace index)"
fi

# --- Test 17: prev cache is created on second run ---
echo ""
echo "=== Test 17: analysis-cache.prev.json created on second run ==="
if [[ -f "$PREV_CACHE_FILE" ]]; then
    if jq . "$PREV_CACHE_FILE" > /dev/null 2>&1; then
        pass "analysis-cache.prev.json exists and is valid JSON"
    else
        fail "analysis-cache.prev.json exists but is invalid JSON"
    fi
else
    fail "analysis-cache.prev.json not created after second run"
fi

# --- Summary ---
echo ""
echo "====================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "====================================="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
