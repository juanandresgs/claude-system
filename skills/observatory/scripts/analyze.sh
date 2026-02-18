#!/usr/bin/env bash
# analyze.sh — Observatory Stage 1: trace analysis → analysis-cache.json
#
# Purpose: Read trace data from multiple sources and produce a structured
#          analysis-cache.json with data quality signals, temporal trends,
#          and agent-type breakdowns. This is the foundation of the self-
#          improving flywheel — bad data quality here is itself the first
#          signal to fix.
#
# @decision DEC-OBS-006
# @title Single-pass jq aggregation for trace stats
# @status accepted
# @rationale The trace index has 320+ entries and grows over time. Using
#             `jq -sc` reads the entire file in one pass and aggregates all
#             stats in a single jq expression, hitting the <2s performance
#             target. Multi-pass approaches (one jq call per stat) would be
#             O(N * queries) and visibly slow at scale.
#
# @decision DEC-OBS-007
# @title Hardcoded signal detection with evidence thresholds
# @status accepted
# @rationale The 5 signals are known root causes from code inspection, not
#             discovered dynamically. Hardcoding them with evidence thresholds
#             (affected_count > 0) means: signals only appear when the data
#             confirms the bug, and disappear once fixed. This is correct
#             behavior for a self-improving system — the signals document known
#             bugs until the bugs are gone.
#
# @decision DEC-OBS-013
# @title Temporal trends via analysis-cache.prev.json snapshot
# @status accepted
# @rationale Before overwriting analysis-cache.json, copy it to
#             analysis-cache.prev.json. Stage 4b then diffs current vs prev
#             to produce signal_count_delta and per-signal affected deltas.
#             This costs one extra file write but gives the report meaningful
#             trend arrows without any external state. If no prev exists
#             (first run), trends are null (not an error).
#
# Output: ~/.claude/observatory/analysis-cache.json
#         ~/.claude/observatory/analysis-cache.prev.json (previous run snapshot)
# Usage: bash skills/observatory/scripts/analyze.sh

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
WORKTREE_DIR="${WORKTREE_DIR:-$CLAUDE_DIR}"
TRACE_INDEX="${CLAUDE_DIR}/traces/index.jsonl"
TRACE_STORE="${CLAUDE_DIR}/traces"
OBS_DIR="${OBS_DIR:-${WORKTREE_DIR}/observatory}"
CACHE_FILE="${OBS_DIR}/analysis-cache.json"
PREV_CACHE_FILE="${OBS_DIR}/analysis-cache.prev.json"
STATE_FILE="${STATE_FILE:-${OBS_DIR}/state.json}"

# --- Preflight ---
mkdir -p "$OBS_DIR"

if [[ ! -f "$TRACE_INDEX" ]]; then
    echo "ERROR: Trace index not found at $TRACE_INDEX" >&2
    exit 1
fi

# Snapshot previous analysis for trend tracking (Stage 4b)
if [[ -f "$CACHE_FILE" ]]; then
    cp "$CACHE_FILE" "$PREV_CACHE_FILE"
fi

# --- Stage 1: Trace index stats (single-pass jq) ---
TRACE_STATS=$(jq -sc '
  {
    total: length,
    outcome_dist: (
      group_by(.outcome) |
      map({key: (.[0].outcome // "unknown"), value: length}) |
      from_entries
    ),
    test_dist: (
      group_by(.test_result) |
      map({key: (.[0].test_result // "unknown"), value: length}) |
      from_entries
    ),
    files_changed_zero_count: (map(select(.files_changed == 0)) | length),
    negative_duration_count: (map(select(.duration_seconds < 0)) | length),
    zero_duration_count: (map(select(.duration_seconds == 0)) | length)
  }
' "$TRACE_INDEX" 2>/dev/null)

TOTAL=$(echo "$TRACE_STATS" | jq '.total')
FILES_ZERO=$(echo "$TRACE_STATS" | jq '.files_changed_zero_count')
NEG_DUR=$(echo "$TRACE_STATS" | jq '.negative_duration_count')
ZERO_DUR=$(echo "$TRACE_STATS" | jq '.zero_duration_count')
BAD_DUR=$((NEG_DUR + ZERO_DUR))

# Compute percentage of zero files_changed
FILES_ZERO_PCT=$(jq -n "$FILES_ZERO / $TOTAL * 100" 2>/dev/null || echo "0")

# Count unknown test results
UNKNOWN_TEST=$(echo "$TRACE_STATS" | jq '.test_dist.unknown // 0')
PARTIAL_OUTCOME=$(echo "$TRACE_STATS" | jq '.outcome_dist.partial // 0')

# Add files_changed_zero_pct to stats
TRACE_STATS=$(echo "$TRACE_STATS" | jq \
    --argjson pct "$FILES_ZERO_PCT" \
    '. + {files_changed_zero_pct: ($pct | round * 10 / 10)}')

# --- Stage 2: Artifact health (scan actual trace dirs) ---
TOTAL_TRACE_DIRS=0
SUMMARY_EXISTS=0
TEST_OUTPUT_EXISTS=0
DIFF_EXISTS=0
FILES_CHANGED_EXISTS=0

while IFS= read -r trace_dir; do
    artifacts_dir="${trace_dir}/artifacts"
    (( TOTAL_TRACE_DIRS++ ))
    [[ -f "${trace_dir}/summary.md" ]] && (( SUMMARY_EXISTS++ )) || true
    [[ -f "${artifacts_dir}/test-output.txt" ]] && (( TEST_OUTPUT_EXISTS++ )) || true
    [[ -f "${artifacts_dir}/diff.patch" ]] && (( DIFF_EXISTS++ )) || true
    [[ -f "${artifacts_dir}/files-changed.txt" ]] && (( FILES_CHANGED_EXISTS++ )) || true
done < <(find "$TRACE_STORE" -maxdepth 1 -mindepth 1 -type d ! -name '.git' 2>/dev/null | sort)

# Compute completeness rates
compute_rate() {
    local count="$1" total="$2"
    if [[ "$total" -eq 0 ]]; then echo "0"; return; fi
    jq -n "$count / $total" 2>/dev/null || echo "0"
}

SUMMARY_RATE=$(compute_rate "$SUMMARY_EXISTS" "$TOTAL_TRACE_DIRS")
TEST_RATE=$(compute_rate "$TEST_OUTPUT_EXISTS" "$TOTAL_TRACE_DIRS")
DIFF_RATE=$(compute_rate "$DIFF_EXISTS" "$TOTAL_TRACE_DIRS")
FILES_RATE=$(compute_rate "$FILES_CHANGED_EXISTS" "$TOTAL_TRACE_DIRS")

ARTIFACT_HEALTH=$(jq -cn \
    --argjson total "$TOTAL_TRACE_DIRS" \
    --argjson summary "$SUMMARY_RATE" \
    --argjson test_out "$TEST_RATE" \
    --argjson diff "$DIFF_RATE" \
    --argjson files "$FILES_RATE" \
    '{
      total_traces: $total,
      completeness: {
        "summary.md": ($summary | . * 100 | round / 100),
        "test-output.txt": ($test_out | . * 100 | round / 100),
        "diff.patch": ($diff | . * 100 | round / 100),
        "files-changed.txt": ($files | . * 100 | round / 100)
      }
    }')

# --- Stage 3: Self-metrics from state.json ---
SELF_METRICS='{"total_suggestions": 0, "implemented": 0, "rejected": 0, "acceptance_rate": null}'
if [[ -f "$STATE_FILE" ]]; then
    IMPL_COUNT=$(jq '.implemented | length' "$STATE_FILE" 2>/dev/null || echo "0")
    REJ_COUNT=$(jq '.rejected | length' "$STATE_FILE" 2>/dev/null || echo "0")
    TOTAL_SIGS=$((IMPL_COUNT + REJ_COUNT))
    if [[ "$TOTAL_SIGS" -gt 0 ]]; then
        ACCEPT_RATE=$(jq -n "$IMPL_COUNT / $TOTAL_SIGS" 2>/dev/null || echo "null")
    else
        ACCEPT_RATE="null"
    fi
    SELF_METRICS=$(jq -cn \
        --argjson impl "$IMPL_COUNT" \
        --argjson rej "$REJ_COUNT" \
        --argjson total "$TOTAL_SIGS" \
        --argjson rate "$ACCEPT_RATE" \
        '{total_suggestions: $total, implemented: $impl, rejected: $rej, acceptance_rate: $rate}')
fi

# --- Stage 4: Build improvement signals ---
# Only emit a signal when evidence shows the bug is present (affected_count > 0).
# Signals auto-disappear once the underlying bug is fixed.

SIGNALS="[]"

# SIG-DURATION-BUG: negative or zero durations dominate
if [[ "$BAD_DUR" -gt 0 ]]; then
    SIGNALS=$(echo "$SIGNALS" | jq \
        --argjson affected "$BAD_DUR" \
        --argjson total "$TOTAL" \
        '. + [{
          "id": "SIG-DURATION-BUG",
          "category": "data_quality",
          "severity": "high",
          "description": "date -j -f missing -u flag causes negative/zero durations",
          "evidence": {"affected_count": $affected, "total": $total},
          "root_cause": "finalize_trace() in context-lib.sh line 569: date -j -f parses UTC string as local time without -u flag"
        }]')
fi

# SIG-TEST-UNKNOWN: high rate of unknown test results
if [[ "$UNKNOWN_TEST" -gt 0 ]]; then
    SIGNALS=$(echo "$SIGNALS" | jq \
        --argjson affected "$UNKNOWN_TEST" \
        --argjson total "$TOTAL" \
        '. + [{
          "id": "SIG-TEST-UNKNOWN",
          "category": "data_quality",
          "severity": "high",
          "description": "High rate of unknown test_result in trace index",
          "evidence": {"affected_count": $affected, "total": $total},
          "root_cause": "finalize_trace only checks test-output.txt artifact, no fallback to .test-status file in project root"
        }]')
fi

# SIG-FILES-ZERO: high rate of zero files_changed
if [[ "$FILES_ZERO" -gt 0 ]]; then
    SIGNALS=$(echo "$SIGNALS" | jq \
        --argjson affected "$FILES_ZERO" \
        --argjson total "$TOTAL" \
        '. + [{
          "id": "SIG-FILES-ZERO",
          "category": "data_quality",
          "severity": "medium",
          "description": "High rate of zero files_changed in trace index",
          "evidence": {"affected_count": $affected, "total": $total},
          "root_cause": "finalize_trace only checks files-changed.txt artifact, no git diff --stat fallback"
        }]')
fi

# SIG-OUTCOME-FLAT: partial outcome dominates (>50% is a signal)
PARTIAL_THRESHOLD=$(jq -n "$TOTAL * 0.5" | jq 'floor')
if [[ "$PARTIAL_OUTCOME" -gt "$PARTIAL_THRESHOLD" ]]; then
    SIGNALS=$(echo "$SIGNALS" | jq \
        --argjson affected "$PARTIAL_OUTCOME" \
        --argjson total "$TOTAL" \
        '. + [{
          "id": "SIG-OUTCOME-FLAT",
          "category": "data_quality",
          "severity": "medium",
          "description": "Outcome field dominated by partial — classification too binary",
          "evidence": {"affected_count": $affected, "total": $total},
          "root_cause": "Outcome only becomes success if test_result==pass, failure if fail, else partial — no crashed/timeout/skipped states"
        }]')
fi

# SIG-ARTIFACT-MISSING: low artifact completeness (< 20% for summary.md is a signal)
SUMMARY_PCT=$(jq -n "$SUMMARY_EXISTS / ($TOTAL_TRACE_DIRS == 0 | if . then 1 else $TOTAL_TRACE_DIRS end) * 100" 2>/dev/null || echo "100")
LOW_COMPLETENESS_THRESHOLD=20
if (( TOTAL_TRACE_DIRS > 0 )) && \
   [[ $(jq -n "$SUMMARY_PCT < $LOW_COMPLETENESS_THRESHOLD" 2>/dev/null) == "true" ]]; then
    MISSING_ARTIFACT_COUNT=$(( TOTAL_TRACE_DIRS - SUMMARY_EXISTS ))
    SIGNALS=$(echo "$SIGNALS" | jq \
        --argjson affected "$MISSING_ARTIFACT_COUNT" \
        --argjson total "$TOTAL_TRACE_DIRS" \
        '. + [{
          "id": "SIG-ARTIFACT-MISSING",
          "category": "trace_completeness",
          "severity": "medium",
          "description": "Most trace directories lack expected artifacts (summary.md, test-output.txt, etc.)",
          "evidence": {"affected_count": $affected, "total": $total},
          "root_cause": "Agents do not consistently write to TRACE_DIR/artifacts/ — missing TRACE_DIR env or early exit"
        }]')
fi

# --- Stage 4b: Temporal trends (compare with previous run) ---
# If analysis-cache.prev.json exists, compute deltas to detect trends.
TRENDS="null"
if [[ -f "$PREV_CACHE_FILE" ]]; then
    PREV_SIG_COUNT=$(jq '.improvement_signals | length' "$PREV_CACHE_FILE" 2>/dev/null || echo "0")
    CURR_SIG_COUNT=$(echo "$SIGNALS" | jq 'length')
    SIG_DELTA=$((CURR_SIG_COUNT - PREV_SIG_COUNT))

    # Determine trend direction
    if [[ "$SIG_DELTA" -lt 0 ]]; then
        SIG_TREND="improving"
    elif [[ "$SIG_DELTA" -gt 0 ]]; then
        SIG_TREND="worsening"
    else
        SIG_TREND="stable"
    fi

    PREV_TOTAL=$(jq '.trace_stats.total // 0' "$PREV_CACHE_FILE" 2>/dev/null || echo "0")
    TRACE_DELTA=$((TOTAL - PREV_TOTAL))

    # Per-signal affected-count deltas: did affected counts go up or down?
    PER_SIGNAL_TRENDS=$(echo "$SIGNALS" | jq \
        --slurpfile prev <(cat "$PREV_CACHE_FILE") \
        '[.[] | {
          id: .id,
          current_affected: .evidence.affected_count,
          prev_affected: (
            ($prev[0].improvement_signals // []) |
            map(select(.id == .id)) |
            if length > 0 then .[0].evidence.affected_count else null end
          ),
          delta: (
            .evidence.affected_count as $curr |
            (($prev[0].improvement_signals // []) | map(select(.id == .id)) | if length > 0 then .[0].evidence.affected_count else null end) as $prev_val |
            if $prev_val != null then ($curr - $prev_val) else null end
          )
        }]' 2>/dev/null || echo "[]")

    # New signals since last run
    NEW_SIGNALS=$(echo "$SIGNALS" | jq \
        --slurpfile prev <(cat "$PREV_CACHE_FILE") \
        '[.[] | .id] - [($prev[0].improvement_signals // []) | .[].id]' 2>/dev/null || echo "[]")

    TRENDS=$(jq -cn \
        --argjson sig_delta "$SIG_DELTA" \
        --arg sig_trend "$SIG_TREND" \
        --argjson trace_delta "$TRACE_DELTA" \
        --argjson per_signal "$PER_SIGNAL_TRENDS" \
        --argjson new_signals "$NEW_SIGNALS" \
        '{
          signal_count_delta: $sig_delta,
          signal_trend: $sig_trend,
          trace_count_delta: $trace_delta,
          per_signal: $per_signal,
          new_signals: $new_signals
        }')
fi

# --- Stage 4c: Agent-type breakdown ---
# Aggregate traces by agent_type field (if present in index entries).
# Not all entries have agent_type — those without are grouped as "unknown".
AGENT_BREAKDOWN=$(jq -sc '
  group_by(.agent_type // "unknown") |
  map({
    agent_type: (.[0].agent_type // "unknown"),
    count: length,
    outcome_dist: (
      group_by(.outcome) |
      map({key: (.[0].outcome // "unknown"), value: length}) |
      from_entries
    ),
    artifact_rate: (
      (map(select(.files_changed != null and .files_changed > 0)) | length) / length
    ),
    avg_duration: (
      [.[] | select(.duration_seconds != null and .duration_seconds > 0) | .duration_seconds] |
      if length > 0 then (add / length | . * 10 | round / 10) else null end
    )
  }) |
  sort_by(-.count)
' "$TRACE_INDEX" 2>/dev/null || echo "[]")

# --- Stage 5: Assemble and write output ---
GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -cn \
    --arg generated_at "$GENERATED_AT" \
    --argjson trace_stats "$TRACE_STATS" \
    --argjson artifact_health "$ARTIFACT_HEALTH" \
    --argjson self_metrics "$SELF_METRICS" \
    --argjson signals "$SIGNALS" \
    --argjson trends "$TRENDS" \
    --argjson agent_breakdown "$AGENT_BREAKDOWN" \
    '{
      version: 2,
      generated_at: $generated_at,
      trace_stats: $trace_stats,
      artifact_health: $artifact_health,
      self_metrics: $self_metrics,
      improvement_signals: $signals,
      trends: $trends,
      agent_breakdown: $agent_breakdown
    }' > "$CACHE_FILE"

SIG_COUNT=$(echo "$SIGNALS" | jq 'length')
echo "Analysis complete: $TOTAL traces, $SIG_COUNT signals detected → $CACHE_FILE"
