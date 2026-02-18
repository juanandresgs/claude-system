#!/usr/bin/env bash
# test-observatory-flywheel-fix.sh — Tests for SUG-ID instability fix + v1→v3 migration
#
# Purpose: Verify two systemic fixes to the Observatory flywheel:
#   1. v1→v3 migration resolves signal_ids from the hardcoded known-map so that
#      legacy SUG-NNN entries get correct signal_id values (not null).
#   2. suggest.sh skips signals by signal_id (not SUG-ID), so priority renumbering
#      doesn't break the implemented-signal skip logic.
#
# @decision DEC-OBS-023
# @title Flywheel fix tests use real temp dirs and isolated state
# @status accepted
# @rationale Each test creates an isolated OBS_DIR with its own state.json and
#             suggestions/. Tests source state.sh directly and invoke suggest.sh
#             with overridden env vars. No mocks — all real jq/bash evaluation.
#             macOS bash 3.2 compatible (no declare -A).
#
# Test cases:
#   1. v1→v3 migration: 5 known entries produce 5 v3 objects
#   2. Migration resolves all 5 known signal_ids from hardcoded map
#   3. Migration marks sug_id with -legacy suffix on all entries
#   4. Migration sets approximate timestamps (not null)
#   5. suggest.sh skips SIG-TEST-UNKNOWN when in implemented list (signal_id match)
#   6. SUG-ID renumbering doesn't break tracking — signal stays skipped
#   7. Deferred signals (by signal_id) are skipped by suggest.sh
#   8. Cohort regression overrides skip — signal re-proposed despite implemented
#   9. v3 entries survive multiple suggest.sh runs intact
#  10. Unknown signal_id (null) entries do not cause skip of unrelated signals
#
# Usage: bash tests/test-observatory-flywheel-fix.sh
# Returns: 0 if all tests pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="${WORKTREE_ROOT}/skills/observatory/scripts"
STATE_SCRIPT="${SCRIPTS_DIR}/state.sh"
SUGGEST_SCRIPT="${SCRIPTS_DIR}/suggest.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

CLEANUP_DIRS=()
cleanup_all() {
    if [[ "${#CLEANUP_DIRS[@]}" -gt 0 ]]; then
        rm -rf "${CLEANUP_DIRS[@]}" 2>/dev/null || true
    fi
}
trap 'cleanup_all' EXIT

# Create a fresh isolated OBS_DIR
make_test_env() {
    local d
    d=$(mktemp -d)
    CLEANUP_DIRS+=("$d")
    mkdir -p "${d}/obs/suggestions"
    echo "$d"
}

# Write v1 state (plain string array for implemented)
write_state_v1() {
    local state_file="$1"
    local implemented_json="${2:-[]}"
    cat > "$state_file" << EOF
{
  "version": 1,
  "last_analysis_at": null,
  "last_analysis_trace_count": 0,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": ${implemented_json},
  "rejected": [],
  "deferred": []
}
EOF
}

# Write v3 state (object array for implemented)
write_state_v3() {
    local state_file="$1"
    local implemented_json="${2:-[]}"
    local deferred_json="${3:-[]}"
    cat > "$state_file" << EOF
{
  "version": 3,
  "last_analysis_at": null,
  "last_analysis_trace_count": 0,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": ${implemented_json},
  "rejected": [],
  "deferred": ${deferred_json}
}
EOF
}

# Minimal analysis-cache.json with given signals
write_cache() {
    local cache_file="$1"
    shift
    # remaining args: signal ids to include
    local signals_json="[]"
    for sig_id in "$@"; do
        signals_json=$(echo "$signals_json" | jq --arg id "$sig_id" \
            '. + [{
              "id": $id,
              "category": "data_quality",
              "severity": "high",
              "evidence": {
                "affected_count": 10,
                "total": 20,
                "sample": []
              }
            }]')
    done
    jq -cn \
        --argjson signals "$signals_json" \
        '{
          "improvement_signals": $signals,
          "cohort_regressions": []
        }' > "$cache_file"
}

# Write cache with cohort regression for a specific signal
write_cache_with_regression() {
    local cache_file="$1"
    local sig_id="$2"
    # One signal plus a regression entry for it
    jq -cn \
        --arg id "$sig_id" \
        '{
          "improvement_signals": [{
            "id": $id,
            "category": "data_quality",
            "severity": "high",
            "evidence": {
              "affected_count": 10,
              "total": 20,
              "sample": []
            }
          }],
          "cohort_regressions": [{
            "signal_id": $id,
            "regression": true,
            "cohort_size": 15,
            "affected_pct": 0.67
          }]
        }' > "$cache_file"
}

echo "=== Observatory Flywheel Fix Tests ==="
echo ""

# ---------------------------------------------------------------------------
# TEST 1: v1→v3 migration produces 5 objects from 5 string entries
# ---------------------------------------------------------------------------
echo "--- Test 1: v1→v3 migration produces 5 v3 objects ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    write_state_v1 "$sf" '["SUG-001","SUG-002","SUG-004","SUG-005","SUG-006"]'

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export HISTORY_FILE="${d}/obs/history.jsonl"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"

    # Source state.sh and run init_state (triggers migration)
    (
        source "$STATE_SCRIPT"
        init_state
    )

    count=$(jq '.implemented | length' "$sf")
    version=$(jq '.version' "$sf")
    if [[ "$count" -eq 5 && "$version" -eq 3 ]]; then
        pass "v1→v3 migration: 5 entries preserved, version=3"
    else
        fail "v1→v3 migration: expected 5 entries at v3, got count=$count version=$version"
    fi
}

# ---------------------------------------------------------------------------
# TEST 2: Migration resolves correct signal_ids from hardcoded known map
# ---------------------------------------------------------------------------
echo "--- Test 2: Migration resolves known signal_ids ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    write_state_v1 "$sf" '["SUG-001","SUG-002","SUG-004","SUG-005","SUG-006"]'

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export HISTORY_FILE="${d}/obs/history.jsonl"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"

    (
        source "$STATE_SCRIPT"
        init_state
    )

    # Check specific mappings
    sig1=$(jq -r '.implemented[] | select(.sug_id == "SUG-001-legacy") | .signal_id' "$sf")
    sig2=$(jq -r '.implemented[] | select(.sug_id == "SUG-002-legacy") | .signal_id' "$sf")
    sig4=$(jq -r '.implemented[] | select(.sug_id == "SUG-004-legacy") | .signal_id' "$sf")
    sig5=$(jq -r '.implemented[] | select(.sug_id == "SUG-005-legacy") | .signal_id' "$sf")
    sig6=$(jq -r '.implemented[] | select(.sug_id == "SUG-006-legacy") | .signal_id' "$sf")

    errors=0
    [[ "$sig1" == "SIG-TEST-UNKNOWN"       ]] || { echo "  SUG-001 got '$sig1', want SIG-TEST-UNKNOWN"; errors=$((errors+1)); }
    [[ "$sig2" == "SIG-FILES-ZERO"         ]] || { echo "  SUG-002 got '$sig2', want SIG-FILES-ZERO"; errors=$((errors+1)); }
    [[ "$sig4" == "SIG-AGENT-TYPE-MISMATCH" ]] || { echo "  SUG-004 got '$sig4', want SIG-AGENT-TYPE-MISMATCH"; errors=$((errors+1)); }
    [[ "$sig5" == "SIG-BRANCH-UNKNOWN"     ]] || { echo "  SUG-005 got '$sig5', want SIG-BRANCH-UNKNOWN"; errors=$((errors+1)); }
    [[ "$sig6" == "SIG-STALE-MARKERS"      ]] || { echo "  SUG-006 got '$sig6', want SIG-STALE-MARKERS"; errors=$((errors+1)); }

    if [[ "$errors" -eq 0 ]]; then
        pass "Migration resolves all 5 known signal_ids correctly"
    else
        fail "Migration signal_id resolution: $errors error(s)"
    fi
}

# ---------------------------------------------------------------------------
# TEST 3: Migration marks sug_id with -legacy suffix
# ---------------------------------------------------------------------------
echo "--- Test 3: Migration applies -legacy suffix to sug_ids ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    write_state_v1 "$sf" '["SUG-001","SUG-002","SUG-004","SUG-005","SUG-006"]'

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export HISTORY_FILE="${d}/obs/history.jsonl"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"

    (
        source "$STATE_SCRIPT"
        init_state
    )

    # All sug_ids should end with -legacy
    non_legacy=$(jq '[.implemented[] | select(.sug_id | endswith("-legacy") | not)] | length' "$sf")
    if [[ "$non_legacy" -eq 0 ]]; then
        pass "All migrated sug_ids have -legacy suffix"
    else
        fail "Expected all sug_ids to have -legacy suffix, got $non_legacy without it"
        jq '[.implemented[].sug_id]' "$sf"
    fi
}

# ---------------------------------------------------------------------------
# TEST 4: Migration sets approximate timestamps (not null)
# ---------------------------------------------------------------------------
echo "--- Test 4: Migration sets non-null implemented_at timestamps ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    write_state_v1 "$sf" '["SUG-001","SUG-002","SUG-004","SUG-005","SUG-006"]'

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export HISTORY_FILE="${d}/obs/history.jsonl"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"

    (
        source "$STATE_SCRIPT"
        init_state
    )

    null_ts=$(jq '[.implemented[] | select(.implemented_at == null)] | length' "$sf")
    if [[ "$null_ts" -eq 0 ]]; then
        pass "All migrated entries have non-null implemented_at timestamps"
    else
        fail "Expected 0 null implemented_at, got $null_ts"
    fi
}

# ---------------------------------------------------------------------------
# TEST 5: suggest.sh skips SIG-TEST-UNKNOWN when in implemented list (signal_id match)
# ---------------------------------------------------------------------------
echo "--- Test 5: suggest.sh skips signal by signal_id match ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    cf="${d}/obs/analysis-cache.json"

    # v3 state with SIG-TEST-UNKNOWN implemented
    write_state_v3 "$sf" \
        '[{"sug_id":"SUG-001-legacy","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"2026-02-18T03:00:00Z"}]'

    # Cache with only SIG-TEST-UNKNOWN as a signal
    write_cache "$cf" "SIG-TEST-UNKNOWN"

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"
    export WORKTREE_DIR="${WORKTREE_ROOT}"

    output=$(bash "$SUGGEST_SCRIPT" 2>&1)

    if echo "$output" | grep -q "SIG-TEST-UNKNOWN"; then
        # Check if it was skipped (not created)
        sug_count=$(ls "${d}/obs/suggestions/"*.json 2>/dev/null | wc -l | tr -d ' ')
        if echo "$output" | grep -q "Skipping.*SIG-TEST-UNKNOWN" && [[ "$sug_count" -eq 0 ]]; then
            pass "suggest.sh skips SIG-TEST-UNKNOWN by signal_id match"
        elif [[ "$sug_count" -eq 0 ]]; then
            pass "suggest.sh skips SIG-TEST-UNKNOWN (no output file created)"
        else
            fail "SIG-TEST-UNKNOWN was NOT skipped: $sug_count suggestion files created"
            echo "  Output: $output"
        fi
    else
        # Signal not mentioned at all — check no files created
        sug_count=$(ls "${d}/obs/suggestions/"*.json 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$sug_count" -eq 0 ]]; then
            pass "suggest.sh skips SIG-TEST-UNKNOWN (no output file created)"
        else
            fail "SIG-TEST-UNKNOWN unexpectedly created $sug_count suggestion file(s)"
            echo "  Output: $output"
        fi
    fi
}

# ---------------------------------------------------------------------------
# TEST 6: SUG-ID renumbering doesn't break tracking
# ---------------------------------------------------------------------------
echo "--- Test 6: SUG-ID renumbering doesn't break implemented-signal tracking ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    cf="${d}/obs/analysis-cache.json"

    # Two signals in v3 state
    write_state_v3 "$sf" \
        '[
          {"sug_id":"SUG-001-legacy","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"2026-02-18T03:00:00Z"},
          {"sug_id":"SUG-002-legacy","signal_id":"SIG-FILES-ZERO","implemented_at":"2026-02-18T03:00:00Z"}
        ]'

    # Cache has SIG-FILES-ZERO (which was SUG-002, but renumbered if other signals appeared)
    write_cache "$cf" "SIG-FILES-ZERO"

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"
    export WORKTREE_DIR="${WORKTREE_ROOT}"

    bash "$SUGGEST_SCRIPT" > /dev/null 2>&1

    sug_count=$(ls "${d}/obs/suggestions/"*.json 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$sug_count" -eq 0 ]]; then
        pass "SUG-ID renumbering: SIG-FILES-ZERO still skipped regardless of SUG-NNN number"
    else
        fail "SUG-ID renumbering: SIG-FILES-ZERO was NOT skipped ($sug_count file(s) created)"
    fi
}

# ---------------------------------------------------------------------------
# TEST 7: Deferred signals (by signal_id) are skipped by suggest.sh
# ---------------------------------------------------------------------------
echo "--- Test 7: Deferred signals are skipped by suggest.sh ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    cf="${d}/obs/analysis-cache.json"

    # State with SIG-BRANCH-UNKNOWN deferred
    write_state_v3 "$sf" '[]' \
        '[{"sug_id":"SUG-005-legacy","signal_id":"SIG-BRANCH-UNKNOWN","deferred_at":"2026-02-18T03:00:00Z","reason":"user","reassess_after":"2026-03-01T00:00:00Z","reassess_condition":null,"priority_at_deferral":null}]'

    # Cache with SIG-BRANCH-UNKNOWN
    write_cache "$cf" "SIG-BRANCH-UNKNOWN"

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"
    export WORKTREE_DIR="${WORKTREE_ROOT}"

    output=$(bash "$SUGGEST_SCRIPT" 2>&1)
    sug_count=$(ls "${d}/obs/suggestions/"*.json 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$sug_count" -eq 0 ]]; then
        pass "Deferred signal SIG-BRANCH-UNKNOWN skipped by suggest.sh"
    else
        fail "Deferred SIG-BRANCH-UNKNOWN was NOT skipped ($sug_count file(s) created)"
        echo "  Output: $output"
    fi
}

# ---------------------------------------------------------------------------
# TEST 8: Cohort regression overrides skip — signal re-proposed despite implemented
# ---------------------------------------------------------------------------
echo "--- Test 8: Cohort regression overrides implemented-signal skip ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    cf="${d}/obs/analysis-cache.json"

    # SIG-AGENT-TYPE-MISMATCH is implemented but has a cohort regression
    write_state_v3 "$sf" \
        '[{"sug_id":"SUG-004-legacy","signal_id":"SIG-AGENT-TYPE-MISMATCH","implemented_at":"2026-02-18T04:00:00Z"}]'

    write_cache_with_regression "$cf" "SIG-AGENT-TYPE-MISMATCH"

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"
    export WORKTREE_DIR="${WORKTREE_ROOT}"

    output=$(bash "$SUGGEST_SCRIPT" 2>&1)
    sug_count=$(ls "${d}/obs/suggestions/"*.json 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$sug_count" -gt 0 ]]; then
        # Verify it was re-proposed with regression=true
        regression=$(jq -r '.regression' "${d}/obs/suggestions/SUG-001.json" 2>/dev/null || echo "false")
        if [[ "$regression" == "true" ]]; then
            pass "Cohort regression overrides skip: signal re-proposed with regression=true"
        else
            fail "Signal re-proposed but regression flag is '$regression', expected 'true'"
        fi
    else
        fail "Cohort regression override failed: no suggestion file created"
        echo "  Output: $output"
    fi
}

# ---------------------------------------------------------------------------
# TEST 9: v3 entries survive multiple suggest.sh runs intact
# ---------------------------------------------------------------------------
echo "--- Test 9: v3 implemented entries survive multiple suggest.sh runs ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    cf="${d}/obs/analysis-cache.json"

    write_state_v3 "$sf" \
        '[
          {"sug_id":"SUG-001-legacy","signal_id":"SIG-TEST-UNKNOWN","implemented_at":"2026-02-18T03:00:00Z"},
          {"sug_id":"SUG-002-legacy","signal_id":"SIG-FILES-ZERO","implemented_at":"2026-02-18T03:00:00Z"}
        ]'

    # Cache with a NEW signal (not implemented)
    write_cache "$cf" "SIG-STALE-MARKERS"

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"
    export WORKTREE_DIR="${WORKTREE_ROOT}"

    # Run suggest.sh twice
    bash "$SUGGEST_SCRIPT" > /dev/null 2>&1
    bash "$SUGGEST_SCRIPT" > /dev/null 2>&1

    # Check that original implemented entries are still in state (suggest.sh is read-only for state)
    count=$(jq '.implemented | length' "$sf")
    sig1=$(jq -r '.implemented[] | select(.signal_id == "SIG-TEST-UNKNOWN") | .signal_id' "$sf" | head -1)
    sig2=$(jq -r '.implemented[] | select(.signal_id == "SIG-FILES-ZERO") | .signal_id' "$sf" | head -1)

    if [[ "$count" -eq 2 && "$sig1" == "SIG-TEST-UNKNOWN" && "$sig2" == "SIG-FILES-ZERO" ]]; then
        pass "v3 implemented entries survive multiple suggest.sh runs"
    else
        fail "v3 entries corrupted after suggest.sh runs: count=$count"
        jq '.implemented' "$sf"
    fi
}

# ---------------------------------------------------------------------------
# TEST 10: Null signal_id entries do not cause skip of unrelated signals
# ---------------------------------------------------------------------------
echo "--- Test 10: Null signal_id entries don't pollute implemented-signal check ---"
{
    d=$(make_test_env)
    sf="${d}/obs/state.json"
    cf="${d}/obs/analysis-cache.json"

    # One entry with null signal_id (e.g. a fully-legacy entry that couldn't be resolved)
    write_state_v3 "$sf" \
        '[{"sug_id":"SUG-003-legacy","signal_id":null,"implemented_at":"2026-02-18T03:00:00Z"}]'

    # Cache with a signal that is NOT implemented
    write_cache "$cf" "SIG-STALE-MARKERS"

    export OBS_DIR="${d}/obs"
    export STATE_FILE="$sf"
    export SUGGESTIONS_DIR="${d}/obs/suggestions"
    export WORKTREE_DIR="${WORKTREE_ROOT}"

    bash "$SUGGEST_SCRIPT" > /dev/null 2>&1
    sug_count=$(ls "${d}/obs/suggestions/"*.json 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$sug_count" -gt 0 ]]; then
        pass "Null signal_id entries don't block unrelated signal SIG-STALE-MARKERS"
    else
        fail "SIG-STALE-MARKERS was skipped (likely due to null signal_id pollution)"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
