#!/usr/bin/env bash
# test_report.sh — Unit tests for observatory report.sh
#
# Purpose: Verify report.sh produces a valid assessment-report.md containing
#          all required sections from known fixture data.
#
# @decision DEC-OBS-004
# @title Use fixture data for report.sh tests
# @status accepted
# @rationale report.sh is a pure synthesis step that reads analysis-cache.json,
#             comparison-matrix.json, and state.json. Using fixtures with known
#             content lets us assert exact section presence and table structure
#             without environment sensitivity.
#
# Usage: bash tests/observatory/test_report.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
WORKTREE="${CLAUDE_DIR}/.worktrees/feat-observatory-v2"
REPORT_SCRIPT="${WORKTREE}/skills/observatory/scripts/report.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Setup: isolated test environment ---
TEST_OBS_DIR=$(mktemp -d)
trap "rm -rf $TEST_OBS_DIR" EXIT

export OBS_DIR="$TEST_OBS_DIR"
export STATE_FILE="${TEST_OBS_DIR}/state.json"
export WORKTREE_DIR="$WORKTREE"

CACHE_FILE="${TEST_OBS_DIR}/analysis-cache.json"
MATRIX_FILE="${TEST_OBS_DIR}/comparison-matrix.json"
SUGGESTIONS_DIR="${TEST_OBS_DIR}/suggestions"
REPORT_FILE="${TEST_OBS_DIR}/assessment-report.md"
mkdir -p "$SUGGESTIONS_DIR"

echo "Setting up fixture data for report.sh tests..."

# --- Fixture: analysis-cache.json ---
cat > "$CACHE_FILE" << 'EOF'
{
  "version": 2,
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
    "total_suggestions": 2,
    "implemented": 1,
    "rejected": 1,
    "acceptance_rate": 0.5
  },
  "improvement_signals": [
    {
      "id": "SIG-DURATION-BUG",
      "category": "data_quality",
      "severity": "high",
      "description": "date -j -f missing -u flag causes negative/zero durations",
      "evidence": {"affected_count": 271, "total": 320},
      "root_cause": "finalize_trace() context-lib.sh line 569"
    },
    {
      "id": "SIG-TEST-UNKNOWN",
      "category": "data_quality",
      "severity": "high",
      "description": "97.5% unknown test_result",
      "evidence": {"affected_count": 312, "total": 320},
      "root_cause": "finalize_trace only checks test-output.txt artifact"
    }
  ],
  "trends": {
    "signal_count_delta": -1,
    "signal_trend": "improving",
    "trace_count_delta": 5,
    "per_signal": [],
    "new_signals": []
  },
  "agent_breakdown": [
    {"agent_type": "implementer", "count": 83, "outcome_dist": {"partial": 60, "success": 10, "crashed": 13}, "artifact_rate": 0.14, "avg_duration": 407.5},
    {"agent_type": "guardian", "count": 109, "outcome_dist": {"partial": 100, "success": 5, "crashed": 4}, "artifact_rate": 0, "avg_duration": 95.7}
  ]
}
EOF

# --- Fixture: comparison-matrix.json ---
cat > "$MATRIX_FILE" << 'EOF'
{
  "matrix": [
    {
      "sug_id": "SUG-001",
      "signal_id": "SIG-DURATION-BUG",
      "severity": "high",
      "affected_pct": 85,
      "priority": 0.812,
      "effort": "low",
      "blast": "function",
      "batch": "A",
      "files": ["hooks/context-lib.sh"],
      "depends_on": [],
      "unlocks": ["SIG-OUTCOME-FLAT"],
      "status": "proposed"
    },
    {
      "sug_id": "SUG-002",
      "signal_id": "SIG-TEST-UNKNOWN",
      "severity": "high",
      "affected_pct": 98,
      "priority": 0.585,
      "effort": "medium",
      "blast": "function",
      "batch": "A",
      "files": ["hooks/context-lib.sh"],
      "depends_on": [],
      "unlocks": ["SIG-OUTCOME-FLAT"],
      "status": "proposed"
    }
  ],
  "batches": {
    "A": {
      "label": "A",
      "signals": ["SIG-DURATION-BUG", "SIG-TEST-UNKNOWN"],
      "files": ["hooks/context-lib.sh"],
      "combined_effort": "medium"
    }
  },
  "effort_buckets": {
    "quick_wins": ["SUG-001"],
    "moderate": ["SUG-002"],
    "deep": []
  }
}
EOF

# --- Fixture: SUG files ---
cat > "${SUGGESTIONS_DIR}/SUG-001.json" << 'EOF'
{
  "id": "SUG-001",
  "status": "proposed",
  "signal_id": "SIG-DURATION-BUG",
  "title": "Fix UTC timezone bug in finalize_trace duration calculation",
  "description": "Add -u flag to date -j -f on line 569 of context-lib.sh",
  "impact": {"scope": "271 of 320 traces (85%)", "severity": "high"},
  "implementation": {"files_to_modify": ["hooks/context-lib.sh"], "approach": "Add -u flag", "test_strategy": "Unit test UTC timestamp"},
  "priority_score": 0.812,
  "batch": "A",
  "depends_on": [],
  "unlocks": ["SIG-OUTCOME-FLAT"]
}
EOF

cat > "${SUGGESTIONS_DIR}/SUG-002.json" << 'EOF'
{
  "id": "SUG-002",
  "status": "proposed",
  "signal_id": "SIG-TEST-UNKNOWN",
  "title": "Add .test-status fallback to finalize_trace",
  "description": "Add fallback for test-status detection",
  "impact": {"scope": "312 of 320 traces (98%)", "severity": "high"},
  "implementation": {"files_to_modify": ["hooks/context-lib.sh"], "approach": "Add fallback", "test_strategy": "Test with mock trace"},
  "priority_score": 0.585,
  "batch": "A",
  "depends_on": [],
  "unlocks": ["SIG-OUTCOME-FLAT"]
}
EOF

# --- Fixture: state.json (with one deferred item) ---
cat > "$STATE_FILE" << 'EOF'
{
  "version": 2,
  "last_analysis_at": "2026-02-17T00:00:00Z",
  "last_analysis_trace_count": 320,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": ["SUG-000"],
  "rejected": ["SUG-X01"],
  "deferred": [
    {
      "sug_id": "SUG-003",
      "signal_id": "SIG-OUTCOME-FLAT",
      "deferred_at": "2026-02-17T00:00:00Z",
      "reason": "dependency",
      "reassess_after": "2026-02-24T00:00:00Z",
      "reassess_condition": "after SIG-DURATION-BUG is implemented",
      "priority_at_deferral": 0.341
    }
  ]
}
EOF

# Override MATRIX_FILE and CACHE_FILE for report.sh via env
export OBS_DIR="$TEST_OBS_DIR"
export STATE_FILE="${TEST_OBS_DIR}/state.json"

# --- Test 1: report.sh runs without error ---
echo ""
echo "=== Test 1: report.sh execution ==="
if bash "$REPORT_SCRIPT" 2>&1; then
    pass "report.sh exits 0"
else
    fail "report.sh exited non-zero"
fi

# --- Test 2: assessment-report.md created ---
echo ""
echo "=== Test 2: assessment-report.md created ==="
if [[ -f "$REPORT_FILE" ]]; then
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" | tr -d ' ')
    pass "assessment-report.md created ($REPORT_SIZE bytes)"
else
    fail "assessment-report.md not found at $REPORT_FILE"
fi

# Bail if no report file
if [[ ! -f "$REPORT_FILE" ]]; then
    echo "RESULTS: $PASS passed, $FAIL failed (aborted — no report file)"
    exit 1
fi

# --- Test 3: Required sections present ---
echo ""
echo "=== Test 3: Required report sections ==="
REQUIRED_SECTIONS=(
    "System Health Summary"
    "Signal Landscape"
    "Batch Analysis"
    "Dependency Map"
    "Effort Buckets"
    "Deferred / Backlog"
    "Observatory Self-Metrics"
)
for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "$section" "$REPORT_FILE"; then
        pass "Section present: $section"
    else
        fail "Section missing: $section"
    fi
done

# --- Test 4: System Health Summary contains key stats ---
echo ""
echo "=== Test 4: System Health Summary stats ==="
if grep -q "365\|320\|Total Traces" "$REPORT_FILE" 2>/dev/null || grep -q "320" "$REPORT_FILE"; then
    pass "Report contains trace count"
else
    fail "Report does not contain trace count"
fi

if grep -q "Active Signals" "$REPORT_FILE"; then
    pass "Report contains Active Signals metric"
else
    fail "Report missing Active Signals metric"
fi

# --- Test 5: Signal Landscape table present with correct columns ---
echo ""
echo "=== Test 5: Signal Landscape table ==="
if grep -q "| # | Signal | Severity |" "$REPORT_FILE"; then
    pass "Signal Landscape table has correct header"
else
    fail "Signal Landscape table header missing or malformed"
fi

if grep -q "SIG-DURATION-BUG" "$REPORT_FILE"; then
    pass "SIG-DURATION-BUG appears in signal landscape"
else
    fail "SIG-DURATION-BUG not found in report"
fi

if grep -q "SIG-TEST-UNKNOWN" "$REPORT_FILE"; then
    pass "SIG-TEST-UNKNOWN appears in signal landscape"
else
    fail "SIG-TEST-UNKNOWN not found in report"
fi

# --- Test 6: Batch Analysis section has batch A ---
echo ""
echo "=== Test 6: Batch Analysis content ==="
if grep -q "Batch A" "$REPORT_FILE"; then
    pass "Batch A present in Batch Analysis section"
else
    fail "Batch A not found in Batch Analysis"
fi

if grep -q "hooks/context-lib.sh" "$REPORT_FILE"; then
    pass "context-lib.sh mentioned in batch analysis"
else
    fail "context-lib.sh not mentioned in report"
fi

# --- Test 7: Dependency Map shows unlock relationships ---
echo ""
echo "=== Test 7: Dependency Map content ==="
if grep -q "SIG-OUTCOME-FLAT" "$REPORT_FILE"; then
    pass "SIG-OUTCOME-FLAT appears in Dependency Map"
else
    fail "SIG-OUTCOME-FLAT not found in report (expected in Dependency Map)"
fi

if grep -q "unlocks" "$REPORT_FILE"; then
    pass "Dependency Map has unlock relationships"
else
    fail "Dependency Map missing unlock relationships"
fi

# --- Test 8: Effort Buckets populated ---
echo ""
echo "=== Test 8: Effort Buckets content ==="
if grep -q "Quick Wins" "$REPORT_FILE"; then
    pass "Quick Wins bucket present"
else
    fail "Quick Wins bucket missing"
fi

if grep -q "SUG-001" "$REPORT_FILE"; then
    pass "SUG-001 appears in report (quick win)"
else
    fail "SUG-001 not found in Effort Buckets"
fi

# --- Test 9: Deferred/Backlog section shows deferred item ---
echo ""
echo "=== Test 9: Deferred/Backlog content ==="
if grep -q "SUG-003" "$REPORT_FILE"; then
    pass "SUG-003 appears in Deferred/Backlog"
else
    fail "SUG-003 not found in deferred section"
fi

if grep -q "SIG-OUTCOME-FLAT" "$REPORT_FILE"; then
    pass "Deferred item signal_id (SIG-OUTCOME-FLAT) visible"
else
    fail "Deferred item signal_id missing from backlog section"
fi

# --- Test 10: Observatory Self-Metrics shows acceptance rate ---
echo ""
echo "=== Test 10: Observatory Self-Metrics ==="
if grep -q "Acceptance rate" "$REPORT_FILE" || grep -q "acceptance_rate\|Implemented" "$REPORT_FILE"; then
    pass "Self-Metrics section has acceptance rate or implemented count"
else
    fail "Self-Metrics missing acceptance rate"
fi

# --- Test 11: Agent-Type Breakdown table present ---
echo ""
echo "=== Test 11: Agent-Type Breakdown table ==="
if grep -q "Agent-Type Breakdown\|Agent Type" "$REPORT_FILE"; then
    pass "Agent-Type Breakdown table present"
else
    fail "Agent-Type Breakdown table missing"
fi

if grep -q "implementer" "$REPORT_FILE"; then
    pass "implementer agent type in breakdown"
else
    fail "implementer not found in agent breakdown"
fi

# --- Test 12: Trend direction reported ---
echo ""
echo "=== Test 12: Trend direction in report ==="
if grep -q "improving\|worsening\|stable\|Trend" "$REPORT_FILE"; then
    pass "Trend direction present in System Health Summary"
else
    fail "Trend direction missing from report"
fi

# --- Test 13: Idempotent — running twice produces same structure ---
echo ""
echo "=== Test 13: Idempotent report generation ==="
bash "$REPORT_SCRIPT" > /dev/null 2>&1
FIRST_LINE_COUNT=$(wc -l < "$REPORT_FILE" | tr -d ' ')
bash "$REPORT_SCRIPT" > /dev/null 2>&1
SECOND_LINE_COUNT=$(wc -l < "$REPORT_FILE" | tr -d ' ')
if [[ "$FIRST_LINE_COUNT" -eq "$SECOND_LINE_COUNT" ]]; then
    pass "Report has same line count on repeated runs ($FIRST_LINE_COUNT lines)"
else
    fail "Report line count changed: $FIRST_LINE_COUNT → $SECOND_LINE_COUNT (not idempotent)"
fi

# --- Summary ---
echo ""
echo "====================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "====================================="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
