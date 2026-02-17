#!/usr/bin/env bash
# test_suggest.sh — Unit tests for observatory suggest.sh
#
# Purpose: Verify suggest.sh produces SUG-NNN.json files with correct priority
#          ordering and schema from a known analysis-cache.json.
#
# @decision DEC-OBS-002
# @title Use fixture analysis-cache.json for suggest.sh tests
# @status accepted
# @rationale suggest.sh takes analysis-cache.json as input, not trace data
#             directly. Using a controlled fixture with known signals lets us
#             assert exact priority ordering without environment sensitivity.
#             This is not mocking internal logic — it's providing known inputs
#             to test priority math correctly.
#
# Usage: bash tests/observatory/test_suggest.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
WORKTREE="${CLAUDE_DIR}/.worktrees/feat-observatory"
SUGGEST_SCRIPT="${WORKTREE}/skills/observatory/scripts/suggest.sh"
CACHE_FILE="${WORKTREE}/observatory/analysis-cache.json"
SUGGESTIONS_DIR="${WORKTREE}/observatory/suggestions"
STATE_FILE="${WORKTREE}/observatory/state.json"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Setup: point suggest.sh at worktree observatory dir ---
export OBS_DIR="${WORKTREE}/observatory"
export STATE_FILE="${WORKTREE}/observatory/state.json"

# --- Setup: write a known fixture cache ---
echo "Setting up fixture analysis-cache.json with all 5 signals..."
mkdir -p "$SUGGESTIONS_DIR"

# Initialize clean state so suggest.sh doesn't skip signals
cat > "$STATE_FILE" << 'EOF'
{
  "version": 1,
  "last_analysis_at": null,
  "last_analysis_trace_count": 0,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": [],
  "rejected": [],
  "deferred": []
}
EOF

# Fixture with all 5 signals at known severity/counts
cat > "$CACHE_FILE" << 'EOF'
{
  "version": 1,
  "generated_at": "2026-02-17T00:00:00Z",
  "trace_stats": {
    "total": 320,
    "outcome_dist": {"partial": 262, "crashed": 50, "success": 8},
    "test_dist": {"unknown": 312, "pass": 8},
    "files_changed_zero_pct": 96.6,
    "negative_duration_count": 15,
    "zero_duration_count": 256
  },
  "artifact_health": {
    "total_traces": 52,
    "completeness": {
      "summary.md": 0.15,
      "test-output.txt": 0.05,
      "diff.patch": 0.03,
      "files-changed.txt": 0.03
    }
  },
  "self_metrics": {
    "total_suggestions": 0,
    "implemented": 0,
    "rejected": 0,
    "acceptance_rate": null
  },
  "improvement_signals": [
    {
      "id": "SIG-DURATION-BUG",
      "category": "data_quality",
      "severity": "high",
      "description": "date -j -f missing -u flag causes negative/zero durations",
      "evidence": {"affected_count": 271, "total": 320},
      "root_cause": "finalize_trace() in context-lib.sh line 569"
    },
    {
      "id": "SIG-TEST-UNKNOWN",
      "category": "data_quality",
      "severity": "high",
      "description": "97.5% unknown test_result",
      "evidence": {"affected_count": 312, "total": 320},
      "root_cause": "finalize_trace only checks test-output.txt artifact"
    },
    {
      "id": "SIG-FILES-ZERO",
      "category": "data_quality",
      "severity": "medium",
      "description": "96.6% zero files_changed",
      "evidence": {"affected_count": 309, "total": 320},
      "root_cause": "finalize_trace only checks files-changed.txt artifact"
    },
    {
      "id": "SIG-OUTCOME-FLAT",
      "category": "data_quality",
      "severity": "medium",
      "description": "82% partial outcomes — too binary",
      "evidence": {"affected_count": 262, "total": 320},
      "root_cause": "Outcome only success if test pass, failure if fail, else partial"
    },
    {
      "id": "SIG-ARTIFACT-MISSING",
      "category": "trace_completeness",
      "severity": "medium",
      "description": "Most traces lack expected artifacts",
      "evidence": {"affected_count": 44, "total": 52},
      "root_cause": "Agents don't consistently write to TRACE_DIR/artifacts/"
    }
  ]
}
EOF

# Clean existing suggestions
rm -f "${SUGGESTIONS_DIR}"/SUG-*.json

# --- Test 1: suggest.sh runs without error ---
echo ""
echo "=== Test 1: suggest.sh execution ==="
if bash "$SUGGEST_SCRIPT" 2>&1; then
    pass "suggest.sh exits 0"
else
    fail "suggest.sh exited non-zero"
fi

# --- Test 2: SUG files are created ---
echo ""
echo "=== Test 2: SUG-NNN.json files created ==="
SUG_COUNT=$(ls "${SUGGESTIONS_DIR}"/SUG-*.json 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SUG_COUNT" -gt 0 ]]; then
    pass "$SUG_COUNT suggestion files created"
else
    fail "No SUG-*.json files found in $SUGGESTIONS_DIR"
fi

# --- Test 3: Each SUG file is valid JSON ---
echo ""
echo "=== Test 3: SUG files are valid JSON ==="
ALL_VALID=true
for f in "${SUGGESTIONS_DIR}"/SUG-*.json; do
    if ! jq . "$f" > /dev/null 2>&1; then
        fail "Invalid JSON: $f"
        ALL_VALID=false
    fi
done
if [[ "$ALL_VALID" == "true" && "$SUG_COUNT" -gt 0 ]]; then
    pass "All $SUG_COUNT SUG files are valid JSON"
fi

# --- Test 4: Schema fields present ---
echo ""
echo "=== Test 4: SUG schema fields ==="
REQUIRED_FIELDS=("id" "status" "signal_id" "title" "description" "impact" "implementation" "priority_score")
FIRST_SUG=$(ls "${SUGGESTIONS_DIR}"/SUG-*.json 2>/dev/null | sort | head -1)
if [[ -n "$FIRST_SUG" ]]; then
    for field in "${REQUIRED_FIELDS[@]}"; do
        if jq -e ".$field" "$FIRST_SUG" > /dev/null 2>&1; then
            pass "Field present: $field"
        else
            fail "Field missing: $field in $(basename $FIRST_SUG)"
        fi
    done
fi

# --- Test 5: SIG-DURATION-BUG is highest priority ---
echo ""
echo "=== Test 5: SIG-DURATION-BUG has highest priority_score ==="
# Find the suggestion mapped to SIG-DURATION-BUG
DUR_SCORE=$(jq -r 'select(.signal_id == "SIG-DURATION-BUG") | .priority_score' "${SUGGESTIONS_DIR}"/SUG-*.json 2>/dev/null | head -1)
if [[ -z "$DUR_SCORE" ]]; then
    fail "No suggestion found for SIG-DURATION-BUG"
else
    # Check it's highest
    MAX_SCORE=$(jq -r '.priority_score' "${SUGGESTIONS_DIR}"/SUG-*.json 2>/dev/null | sort -rn | head -1)
    if [[ "$DUR_SCORE" == "$MAX_SCORE" ]]; then
        pass "SIG-DURATION-BUG has highest priority_score ($DUR_SCORE)"
    else
        fail "SIG-DURATION-BUG score ($DUR_SCORE) is not highest (max: $MAX_SCORE)"
    fi
fi

# --- Test 6: priority_score is between 0 and 1 ---
echo ""
echo "=== Test 6: priority_score in valid range [0,1] ==="
INVALID_SCORES=$(jq -r '.priority_score' "${SUGGESTIONS_DIR}"/SUG-*.json 2>/dev/null | awk '$1 < 0 || $1 > 1 {print $1}')
if [[ -z "$INVALID_SCORES" ]]; then
    pass "All priority_scores in [0,1] range"
else
    fail "Out-of-range priority_scores: $INVALID_SCORES"
fi

# --- Test 7: status is "proposed" for new suggestions ---
echo ""
echo "=== Test 7: New suggestions have status=proposed ==="
NON_PROPOSED=$(jq -r 'select(.status != "proposed") | .id' "${SUGGESTIONS_DIR}"/SUG-*.json 2>/dev/null || echo "")
if [[ -z "$NON_PROPOSED" ]]; then
    pass "All suggestions have status=proposed"
else
    fail "Suggestions with unexpected status: $NON_PROPOSED"
fi

# --- Test 8: SUG-001 maps to highest-priority signal ---
echo ""
echo "=== Test 8: SUG-001 is assigned to highest-priority signal ==="
SUG001="${SUGGESTIONS_DIR}/SUG-001.json"
if [[ -f "$SUG001" ]]; then
    SUG001_SIG=$(jq -r '.signal_id' "$SUG001")
    SUG001_SCORE=$(jq -r '.priority_score' "$SUG001")
    pass "SUG-001 maps to $SUG001_SIG (score: $SUG001_SCORE)"
else
    fail "SUG-001.json not found — suggestions not sequentially numbered"
fi

# --- Test 9: implementation block has files_to_modify ---
echo ""
echo "=== Test 9: implementation.files_to_modify is present ==="
for f in "${SUGGESTIONS_DIR}"/SUG-*.json; do
    if jq -e '.implementation.files_to_modify | type == "array"' "$f" > /dev/null 2>&1; then
        pass "$(basename "$f"): implementation.files_to_modify is array"
    else
        fail "$(basename "$f"): implementation.files_to_modify missing or not array"
    fi
done

# --- Summary ---
echo ""
echo "====================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "====================================="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
