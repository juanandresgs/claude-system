#!/usr/bin/env bash
# test-observatory-cohort-regression.sh — Tests for cohort-based regression detection
#
# Purpose: Verify that the Observatory correctly identifies when "implemented"
#          signals still trigger on new traces (post-implementation cohort),
#          and correctly suppresses them when the fix is working.
#
# @decision DEC-OBS-020
# @title Cohort regression tests use real temp dirs and isolated state
# @status accepted
# @rationale Each test creates isolated OBS_DIR, TRACE_INDEX, and state.json
#             to avoid interference. Tests use real jq evaluations, not mocks.
#             This verifies the actual cohort logic in analyze.sh and suggest.sh.
#
# Test cases:
#   1. No regression: new traces clean → signal stays suppressed
#   2. Regression: new traces still trigger → signal re-proposed with regression flag
#   3. Cohort too small (<10 traces) → no regression declared
#   4. Below threshold (<50% affected in cohort) → no regression
#   5. Old format string array → no cohort analysis, signal suppressed normally
#   6. State migration: transition() records new format with signal_id + implemented_at
#
# Usage: bash tests/test-observatory-cohort-regression.sh
# Returns: 0 if all tests pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="${WORKTREE_ROOT}/skills/observatory/scripts"
STATE_SCRIPT="${SCRIPTS_DIR}/state.sh"
ANALYZE_SCRIPT="${SCRIPTS_DIR}/analyze.sh"
SUGGEST_SCRIPT="${SCRIPTS_DIR}/suggest.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

CLEANUP_DIRS=()
# Guard against empty array expansion on bash 3.2 with nounset
cleanup_all() {
    if [[ "${#CLEANUP_DIRS[@]}" -gt 0 ]]; then
        rm -rf "${CLEANUP_DIRS[@]}" 2>/dev/null || true
    fi
}
trap 'cleanup_all' EXIT

# Create a fresh isolated OBS_DIR with companion trace index
make_test_env() {
    local d
    d=$(mktemp -d)
    CLEANUP_DIRS+=("$d")
    mkdir -p "${d}/obs" "${d}/traces" "${d}/obs/suggestions"
    echo "$d"
}

# Write a minimal state.json (v3 schema with implemented-as-objects)
write_state_v3() {
    local state_file="$1"
    local implemented_json="${2:-[]}"
    local rejected_json="${3:-[]}"
    local deferred_json="${4:-[]}"
    cat > "$state_file" << EOF
{
  "version": 3,
  "last_analysis_at": null,
  "last_analysis_trace_count": 0,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": ${implemented_json},
  "rejected": ${rejected_json},
  "deferred": ${deferred_json}
}
EOF
}

# Write a minimal state.json with OLD format (v1: implemented is string array)
write_state_v1() {
    local state_file="$1"
    local implemented_json="${2:-[]}"
    cat > "$state_file" << EOF
{
  "version": 1,
  "pending_suggestion": null,
  "implemented": ${implemented_json},
  "rejected": [],
  "deferred": []
}
EOF
}

# Write N trace entries to a jsonl index.
# Args: file, count, test_result, branch, agent_type, started_at
write_traces() {
    local file="$1"
    local count="$2"
    local test_result="${3:-unknown}"
    local branch="${4:-main}"
    local agent_type="${5:-implementer}"
    local started_at="${6:-2026-02-19T00:00:00Z}"
    local files_changed="${7:-5}"

    > "$file"  # truncate
    for i in $(seq 1 "$count"); do
        jq -cn \
            --arg id "trace-${i}" \
            --arg test_result "$test_result" \
            --arg branch "$branch" \
            --arg agent_type "$agent_type" \
            --arg started_at "$started_at" \
            --argjson files_changed "$files_changed" \
            '{
              id: $id,
              test_result: $test_result,
              branch: $branch,
              agent_type: $agent_type,
              started_at: $started_at,
              files_changed: $files_changed,
              duration_seconds: 120,
              outcome: "partial"
            }' >> "$file"
    done
}

# Append trace entries to an existing index (for mixed pre/post traces)
append_traces() {
    local file="$1"
    local count="$2"
    local test_result="${3:-unknown}"
    local branch="${4:-main}"
    local agent_type="${5:-implementer}"
    local started_at="${6:-2026-02-19T00:00:00Z}"
    local files_changed="${7:-5}"
    local id_offset="${8:-100}"

    for i in $(seq 1 "$count"); do
        jq -cn \
            --arg id "trace-post-$((id_offset + i))" \
            --arg test_result "$test_result" \
            --arg branch "$branch" \
            --arg agent_type "$agent_type" \
            --arg started_at "$started_at" \
            --argjson files_changed "$files_changed" \
            '{
              id: $id,
              test_result: $test_result,
              branch: $branch,
              agent_type: $agent_type,
              started_at: $started_at,
              files_changed: $files_changed,
              duration_seconds: 120,
              outcome: "partial"
            }' >> "$file"
    done
}

# Run analyze.sh in isolation — outputs ONLY the cache file path to stdout.
# analyze.sh's own output goes to stderr (redirected to /dev/null).
run_analyze() {
    local env_dir="$1"
    local obs_dir="${env_dir}/obs"
    local cache_file="${obs_dir}/analysis-cache.json"

    CLAUDE_DIR="$env_dir" \
    WORKTREE_DIR="$env_dir" \
    OBS_DIR="$obs_dir" \
    STATE_FILE="${obs_dir}/state.json" \
    TRACE_INDEX="${env_dir}/traces/index.jsonl" \
    TRACE_STORE="${env_dir}/traces" \
    bash "$ANALYZE_SCRIPT" >/dev/null 2>&1 || true

    echo "$cache_file"
}

# Run suggest.sh in isolation — outputs ONLY the suggestions dir path to stdout.
run_suggest() {
    local env_dir="$1"
    local obs_dir="${env_dir}/obs"

    CLAUDE_DIR="$env_dir" \
    WORKTREE_DIR="$env_dir" \
    OBS_DIR="$obs_dir" \
    STATE_FILE="${obs_dir}/state.json" \
    bash "$SUGGEST_SCRIPT" >/dev/null 2>&1 || true

    echo "${obs_dir}/suggestions"
}

# ===========================================================
# Test 1: No regression — new traces are clean → still suppressed
# ===========================================================
echo ""
echo "=== Test 1: No regression — new traces clean after implementation ==="

ENV1=$(make_test_env)
IMPL_AT_1="2026-02-18T00:00:00Z"

# Write state: SIG-TEST-UNKNOWN was implemented at IMPL_AT_1
write_state_v3 "${ENV1}/obs/state.json" \
    '[{"sug_id":"SUG-001","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"'"$IMPL_AT_1"'"}]'

# Write traces: 5 old (before fix, with unknown) + 15 new (after fix, clean)
write_traces "${ENV1}/traces/index.jsonl" 5 "unknown" "main" "implementer" "2026-02-17T00:00:00Z"
append_traces "${ENV1}/traces/index.jsonl" 15 "pass" "main" "implementer" "2026-02-19T00:00:00Z"

cache_file=$(run_analyze "$ENV1")

# Check: cohort_regressions should be empty (or the signal should not be marked regression)
REGRESSION_COUNT=$(jq '[.cohort_regressions // [] | .[] | select(.signal_id == "SIG-TEST-UNKNOWN" and .regression == true)] | length' "$cache_file" 2>/dev/null || echo "0")

if [[ "$REGRESSION_COUNT" -eq 0 ]]; then
    pass "No regression declared when new traces are clean"
else
    fail "False regression detected when new traces are clean (got $REGRESSION_COUNT)"
fi

# Also verify suggest.sh skips the signal (it should be suppressed)
run_suggest "$ENV1" > /dev/null
SUG_FILES_1=$(ls "${ENV1}/obs/suggestions"/SUG-*.json 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SUG_FILES_1" -eq 0 ]]; then
    pass "Signal suppressed (no SUG files for implemented+clean signal)"
else
    # Check if any of the created suggestions is for SIG-TEST-UNKNOWN without regression flag
    REGRESSION_SUG=$(jq -r 'select(.signal_id == "SIG-TEST-UNKNOWN") | .regression // false' \
        "${ENV1}/obs/suggestions"/SUG-*.json 2>/dev/null | grep "true" | wc -l | tr -d ' ')
    if [[ "$REGRESSION_SUG" -eq 0 ]]; then
        pass "Signal suppressed without regression flag"
    else
        fail "Signal marked as regression when it should be clean"
    fi
fi

# ===========================================================
# Test 2: Regression detected — new traces still trigger the signal
# ===========================================================
echo ""
echo "=== Test 2: Regression detected — new traces still have the issue ==="

ENV2=$(make_test_env)
IMPL_AT_2="2026-02-18T00:00:00Z"

# State: SIG-TEST-UNKNOWN implemented at IMPL_AT_2
write_state_v3 "${ENV2}/obs/state.json" \
    '[{"sug_id":"SUG-001","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"'"$IMPL_AT_2"'"}]'

# Write 5 old traces + 12 NEW traces still with unknown test_result (regression!)
write_traces "${ENV2}/traces/index.jsonl" 5 "pass" "main" "implementer" "2026-02-17T00:00:00Z"
append_traces "${ENV2}/traces/index.jsonl" 12 "unknown" "main" "implementer" "2026-02-19T00:00:00Z"

cache_file2=$(run_analyze "$ENV2")

REGRESSION_COUNT2=$(jq '[.cohort_regressions // [] | .[] | select(.signal_id == "SIG-TEST-UNKNOWN" and .regression == true)] | length' "$cache_file2" 2>/dev/null || echo "0")

if [[ "$REGRESSION_COUNT2" -gt 0 ]]; then
    pass "Regression correctly detected when new traces still trigger signal"
else
    fail "Regression NOT detected when new traces still trigger signal"
fi

# Also run suggest.sh — should re-propose the signal with regression flag
run_suggest "$ENV2" > /dev/null
REGRESSION_IN_SUG=$(find "${ENV2}/obs/suggestions" -name "SUG-*.json" -exec \
    jq -r 'select(.signal_id == "SIG-TEST-UNKNOWN") | .regression // false' {} \; 2>/dev/null | \
    grep "true" | wc -l | tr -d ' ')

if [[ "$REGRESSION_IN_SUG" -gt 0 ]]; then
    pass "Re-proposed suggestion has regression=true flag"
else
    fail "Re-proposed suggestion missing regression=true flag"
fi

# ===========================================================
# Test 3: Cohort too small (<10 traces) → no regression
# ===========================================================
echo ""
echo "=== Test 3: Cohort too small — fewer than 10 new traces ==="

ENV3=$(make_test_env)
IMPL_AT_3="2026-02-18T00:00:00Z"

write_state_v3 "${ENV3}/obs/state.json" \
    '[{"sug_id":"SUG-001","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"'"$IMPL_AT_3"'"}]'

# Only 8 post-implementation traces (below threshold of 10), all with issue
write_traces "${ENV3}/traces/index.jsonl" 3 "pass" "main" "implementer" "2026-02-17T00:00:00Z"
append_traces "${ENV3}/traces/index.jsonl" 8 "unknown" "main" "implementer" "2026-02-19T00:00:00Z"

cache_file3=$(run_analyze "$ENV3")

REGRESSION_COUNT3=$(jq '[.cohort_regressions // [] | .[] | select(.signal_id == "SIG-TEST-UNKNOWN" and .regression == true)] | length' "$cache_file3" 2>/dev/null || echo "0")

if [[ "$REGRESSION_COUNT3" -eq 0 ]]; then
    pass "No regression with cohort_size < 10 (insufficient data)"
else
    fail "Regression declared with only 8 new traces (should need >= 10)"
fi

# ===========================================================
# Test 4: Below threshold — <50% of new traces affected → no regression
# ===========================================================
echo ""
echo "=== Test 4: Below threshold — <50% of new traces affected ==="

ENV4=$(make_test_env)
IMPL_AT_4="2026-02-18T00:00:00Z"

write_state_v3 "${ENV4}/obs/state.json" \
    '[{"sug_id":"SUG-001","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"'"$IMPL_AT_4"'"}]'

# 20 new traces: 8 unknown (40%) + 12 pass (60%) — below 50% threshold
write_traces "${ENV4}/traces/index.jsonl" 5 "pass" "main" "implementer" "2026-02-17T00:00:00Z"
append_traces "${ENV4}/traces/index.jsonl" 12 "pass" "main" "implementer" "2026-02-19T00:00:00Z"
append_traces "${ENV4}/traces/index.jsonl" 8 "unknown" "main" "implementer" "2026-02-19T00:00:00Z" 200

cache_file4=$(run_analyze "$ENV4")

REGRESSION_COUNT4=$(jq '[.cohort_regressions // [] | .[] | select(.signal_id == "SIG-TEST-UNKNOWN" and .regression == true)] | length' "$cache_file4" 2>/dev/null || echo "0")

if [[ "$REGRESSION_COUNT4" -eq 0 ]]; then
    pass "No regression when <50% of new traces are affected (40%)"
else
    fail "False regression when only 40% of new traces are affected"
fi

# ===========================================================
# Test 5: Old format (string array) → no cohort analysis, signal suppressed
# ===========================================================
echo ""
echo "=== Test 5: Old format state.json (string array) — no cohort analysis ==="

ENV5=$(make_test_env)

# Old v1 format: implemented is array of strings
write_state_v1 "${ENV5}/obs/state.json" '["SUG-001"]'

# Create SUG-001.json so suggest.sh can map SUG-001 → SIG-TEST-UNKNOWN
mkdir -p "${ENV5}/obs/suggestions"
jq -cn '{id:"SUG-001",signal_id:"SIG-TEST-UNKNOWN",status:"implemented",title:"test"}' \
    > "${ENV5}/obs/suggestions/SUG-001.json"

# 15 new traces all with the issue (would be regression if new format)
write_traces "${ENV5}/traces/index.jsonl" 15 "unknown" "main" "implementer" "2026-02-19T00:00:00Z"

cache_file5=$(run_analyze "$ENV5")

# cohort_regressions should be empty (no implemented_at timestamp to compare against)
REGRESSION_COUNT5=$(jq '[.cohort_regressions // [] | .[] | select(.regression == true)] | length' "$cache_file5" 2>/dev/null || echo "0")

if [[ "$REGRESSION_COUNT5" -eq 0 ]]; then
    pass "Old format: no cohort analysis (no implemented_at timestamps)"
else
    fail "Old format: unexpected regression detection (no timestamps available)"
fi

# Signal should still be suppressed in suggest.sh (old-format skip still works)
run_suggest "$ENV5" > /dev/null
SUGS_5=$(find "${ENV5}/obs/suggestions" -name "SUG-0*.json" 2>/dev/null | wc -l | tr -d ' ')
# SUG-001.json already exists; new suggestions shouldn't include SIG-TEST-UNKNOWN again without regression
TEST_UNKNOWN_REPROPOSED=$(find "${ENV5}/obs/suggestions" -name "SUG-0*.json" -newer "${ENV5}/obs/suggestions/SUG-001.json" \
    -exec jq -r 'select(.signal_id == "SIG-TEST-UNKNOWN") | .signal_id' {} \; 2>/dev/null | wc -l | tr -d ' ')

if [[ "$TEST_UNKNOWN_REPROPOSED" -eq 0 ]]; then
    pass "Old format: SIG-TEST-UNKNOWN stays suppressed (not re-proposed)"
else
    fail "Old format: SIG-TEST-UNKNOWN was unexpectedly re-proposed"
fi

# ===========================================================
# Test 6: State migration — transition() records new format
# ===========================================================
echo ""
echo "=== Test 6: State migration via transition() records signal_id and implemented_at ==="

ENV6=$(make_test_env)

# Source state.sh and call transition to mark SUG-001 as implemented
(
    export OBS_DIR="${ENV6}/obs"
    export STATE_FILE="${ENV6}/obs/state.json"
    export HISTORY_FILE="${ENV6}/obs/history.jsonl"
    export SUGGESTIONS_DIR="${ENV6}/obs/suggestions"
    mkdir -p "${ENV6}/obs/suggestions"

    # Create a suggestion file so transition can find the signal_id
    jq -cn '{id:"SUG-001",signal_id:"SIG-FILES-ZERO",status:"proposed",title:"test files fix"}' \
        > "${ENV6}/obs/suggestions/SUG-001.json"

    source "$STATE_SCRIPT"
    init_state

    # Mark as implemented — should record signal_id and implemented_at
    transition "SUG-001" "implemented" "test files fix" "0.75"
) 2>/dev/null

# Now verify the state.json has the new object format
IMPL_ENTRY=$(jq '.implemented[0]' "${ENV6}/obs/state.json" 2>/dev/null || echo "null")
IMPL_TYPE=$(echo "$IMPL_ENTRY" | jq -r 'type' 2>/dev/null || echo "unknown")

if [[ "$IMPL_TYPE" == "object" ]]; then
    pass "transition() writes object format (not plain string)"
else
    fail "transition() wrote wrong format: got type=$IMPL_TYPE (expected object)"
fi

HAS_SUG_ID=$(echo "$IMPL_ENTRY" | jq -r '.sug_id // empty' 2>/dev/null)
HAS_SIG_ID=$(echo "$IMPL_ENTRY" | jq -r '.signal_id // empty' 2>/dev/null)
HAS_IMPL_AT=$(echo "$IMPL_ENTRY" | jq -r '.implemented_at // empty' 2>/dev/null)

if [[ "$HAS_SUG_ID" == "SUG-001" ]]; then
    pass "transition() records sug_id=SUG-001"
else
    fail "transition() missing sug_id, got: '$HAS_SUG_ID'"
fi

if [[ "$HAS_SIG_ID" == "SIG-FILES-ZERO" ]]; then
    pass "transition() records signal_id=SIG-FILES-ZERO from suggestion file"
else
    fail "transition() missing/wrong signal_id, got: '$HAS_SIG_ID'"
fi

if [[ -n "$HAS_IMPL_AT" ]]; then
    pass "transition() records implemented_at timestamp"
else
    fail "transition() missing implemented_at timestamp"
fi

# ===========================================================
# Test 7: cohort_regressions field exists in analysis-cache.json
# ===========================================================
echo ""
echo "=== Test 7: analysis-cache.json always has cohort_regressions field ==="

ENV7=$(make_test_env)

# Fresh state with no implemented signals
write_state_v3 "${ENV7}/obs/state.json" '[]'
write_traces "${ENV7}/traces/index.jsonl" 5 "pass" "main" "implementer" "2026-02-19T00:00:00Z"

cache_file7=$(run_analyze "$ENV7")

HAS_FIELD=$(jq 'has("cohort_regressions")' "$cache_file7" 2>/dev/null || echo "false")
if [[ "$HAS_FIELD" == "true" ]]; then
    pass "analysis-cache.json always contains cohort_regressions field"
else
    fail "analysis-cache.json missing cohort_regressions field"
fi

IS_ARRAY=$(jq '.cohort_regressions | type == "array"' "$cache_file7" 2>/dev/null || echo "false")
if [[ "$IS_ARRAY" == "true" ]]; then
    pass "cohort_regressions is an array (even when empty)"
else
    fail "cohort_regressions is not an array"
fi

# ===========================================================
# Test 8: v1→v3 migration preserves implemented entries
# ===========================================================
echo ""
echo "=== Test 8: v1 state migration preserves implemented entries as objects ==="

ENV8=$(make_test_env)

# v1 format: flat string array
write_state_v1 "${ENV8}/obs/state.json" '["SUG-001","SUG-002"]'

# Source state.sh — init_state will migrate
(
    export OBS_DIR="${ENV8}/obs"
    export STATE_FILE="${ENV8}/obs/state.json"
    export HISTORY_FILE="${ENV8}/obs/history.jsonl"
    export SUGGESTIONS_DIR="${ENV8}/obs/suggestions"
    mkdir -p "${ENV8}/obs/suggestions"
    source "$STATE_SCRIPT"
    init_state  # triggers migration
) 2>/dev/null

# After migration, implemented should still have 2 entries
IMPL_COUNT_8=$(jq '.implemented | length' "${ENV8}/obs/state.json" 2>/dev/null || echo "0")
if [[ "$IMPL_COUNT_8" -eq 2 ]]; then
    pass "Migration preserves both implemented entries"
else
    fail "Migration lost entries: expected 2, got $IMPL_COUNT_8"
fi

# They should now be objects with implemented_at: null
FIRST_TYPE_8=$(jq -r '.implemented[0] | type' "${ENV8}/obs/state.json" 2>/dev/null || echo "unknown")
if [[ "$FIRST_TYPE_8" == "object" ]]; then
    pass "Migration converts string entries to objects"
else
    fail "Migration did not convert strings to objects (type=$FIRST_TYPE_8)"
fi

FIRST_IMPL_AT=$(jq -r '.implemented[0].implemented_at' "${ENV8}/obs/state.json" 2>/dev/null || echo "x")
if [[ "$FIRST_IMPL_AT" == "null" ]]; then
    pass "Legacy migrated entries have implemented_at=null"
else
    fail "Legacy entries have unexpected implemented_at: '$FIRST_IMPL_AT'"
fi

# ===========================================================
# Summary
# ===========================================================
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
