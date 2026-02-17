#!/usr/bin/env bash
# suggest.sh — Observatory Stage 2: signals → ranked SUG-NNN.json files
#
# Purpose: Read analysis-cache.json signals and produce prioritized suggestion
#          files in observatory/suggestions/. Each suggestion maps one signal
#          to an actionable implementation plan with a computed priority score.
#
# @decision DEC-OBS-008
# @title Priority formula: impact × feasibility × category_weight
# @status accepted
# @rationale Three-factor ranking balances severity (how bad is it), effort
#             (how hard to fix), and strategic alignment (data quality vs
#             completeness). This prevents high-severity-but-impossible fixes
#             from crowding out quick wins, and ensures data quality issues
#             (which unblock all deeper analysis) rank above completeness issues.
#             Formula: priority = impact_score × feasibility_score × category_weight
#             where impact = (affected/total) × severity_mult
#                   feasibility = complexity_factor × blast_radius_factor
#
# @decision DEC-OBS-009
# @title Skip already-implemented suggestions
# @status accepted
# @rationale The state.json implemented list is checked before generating each
#             suggestion. This prevents the flywheel from re-proposing fixes
#             already merged. The state file is the authoritative source of
#             what has been acted on — it persists across sessions.
#
# @decision DEC-OBS-010
# @title Use jq-based metadata lookup instead of bash associative arrays
# @status accepted
# @rationale macOS ships with bash 3.2 which lacks declare -A. Rather than
#             require bash 4+ or use eval-based hacks, signal metadata is
#             stored in a self-contained jq object and queried with jq -r.
#             This is more portable and keeps the metadata co-located with
#             the query logic.
#
# Output: observatory/suggestions/SUG-NNN.json (one per active signal)
# Usage: bash skills/observatory/scripts/suggest.sh

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
WORKTREE_DIR="${WORKTREE_DIR:-$CLAUDE_DIR}"
OBS_DIR="${OBS_DIR:-${WORKTREE_DIR}/observatory}"
CACHE_FILE="${OBS_DIR}/analysis-cache.json"
SUGGESTIONS_DIR="${OBS_DIR}/suggestions"
STATE_FILE="${STATE_FILE:-${OBS_DIR}/state.json}"

# --- Preflight ---
mkdir -p "$SUGGESTIONS_DIR"

if [[ ! -f "$CACHE_FILE" ]]; then
    echo "ERROR: analysis-cache.json not found at $CACHE_FILE — run analyze.sh first" >&2
    exit 1
fi

# --- Signal metadata (jq object, bash 3.2 compatible) ---
# Each entry: { complexity, blast, files, approach, test_strategy, title, desc }
# complexity: low|medium|high  blast: function|file|multi
SIGNAL_METADATA=$(cat << 'METADATA_EOF'
{
  "SIG-DURATION-BUG": {
    "title": "Fix UTC timezone bug in finalize_trace duration calculation",
    "desc": "Add -u flag to date -j -f on line 569 of context-lib.sh so UTC timestamps are parsed correctly instead of as local time",
    "complexity": "low",
    "blast": "function",
    "files": ["hooks/context-lib.sh"],
    "approach": "Add -u flag: change 'date -j -f \"%Y-%m-%dT%H:%M:%SZ\" \"$started_at\" +%s' to 'date -u -j -f \"%Y-%m-%dT%H:%M:%SZ\" \"$started_at\" +%s' on line 569",
    "test": "Unit test with known UTC timestamp: date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-01-01T12:00:00Z' +%s should equal 1735732800"
  },
  "SIG-TEST-UNKNOWN": {
    "title": "Add .test-status fallback to finalize_trace test result detection",
    "desc": "finalize_trace currently only checks for test-output.txt artifact. Most agents write .test-status file to project root instead. Adding a fallback check would resolve 97.5% unknown test results.",
    "complexity": "medium",
    "blast": "function",
    "files": ["hooks/context-lib.sh"],
    "approach": "After lines 583-589: add fallback check for $project_root/.test-status and $project_root/.claude/.test-status files",
    "test": "Create a trace dir with no test-output.txt but with .test-status=pass. Run finalize_trace. Verify test_result=pass in manifest."
  },
  "SIG-FILES-ZERO": {
    "title": "Add git diff --stat fallback to finalize_trace files_changed count",
    "desc": "finalize_trace only reads files-changed.txt artifact. When agents don't write that file, files_changed stays 0. A git diff --stat fallback against the pre-session commit would give accurate counts.",
    "complexity": "medium",
    "blast": "function",
    "files": ["hooks/context-lib.sh"],
    "approach": "After lines 613-616: if files_changed==0, try git -C project_root diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | awk '{print $1}'",
    "test": "Create trace dir with no files-changed.txt but with a git commit. Run finalize_trace. Verify files_changed > 0 in manifest."
  },
  "SIG-OUTCOME-FLAT": {
    "title": "Expand outcome classification beyond success/failure/partial",
    "desc": "The outcome field only has 3 values: success (test pass), failure (test fail), partial (everything else). Richer classification enables better analysis.",
    "complexity": "medium",
    "blast": "function",
    "files": ["hooks/context-lib.sh"],
    "approach": "In finalize_trace outcome logic (lines 604-610): add timeout outcome when duration > 600s and test_result==unknown, add skipped when no artifacts at all",
    "test": "Unit test: trace with duration>600 and no test-output.txt should get outcome=timeout not partial"
  },
  "SIG-ARTIFACT-MISSING": {
    "title": "Add TRACE_DIR validation to agent prompts to ensure artifact writing",
    "desc": "Most traces lack summary.md and other artifacts because agents exit early or don't have TRACE_DIR set. Adding a preflight check and reminder in the implementer/tester prompts would increase compliance.",
    "complexity": "high",
    "blast": "multi",
    "files": ["agents/implementer.md", "agents/tester.md", "hooks/context-lib.sh"],
    "approach": "Add TRACE_DIR check at start of agent prompts. Add artifact-writing reminder in Session End Protocol. Add PostToolUse hook that warns when TRACE_DIR is set but artifacts dir is empty after 30min.",
    "test": "Run implementer with TRACE_DIR set. Verify artifacts/ dir is created and summary.md exists after completion."
  }
}
METADATA_EOF
)

# --- Load already-implemented signal IDs to skip ---
IMPLEMENTED_SIGS=""
if [[ -f "$STATE_FILE" ]]; then
    # Map implemented SUG-IDs back to signal IDs via existing suggestion files
    while IFS= read -r sug_id; do
        sug_file="${SUGGESTIONS_DIR}/${sug_id}.json"
        if [[ -f "$sug_file" ]]; then
            sig_id=$(jq -r '.signal_id' "$sug_file" 2>/dev/null || echo "")
            [[ -n "$sig_id" ]] && IMPLEMENTED_SIGS="${IMPLEMENTED_SIGS} ${sig_id}"
        fi
    done < <(jq -r '.implemented[]' "$STATE_FILE" 2>/dev/null || true)
fi

# --- Compute priority scores for each signal ---
SCORE_LIST=""

while IFS= read -r signal; do
    SIG_ID=$(echo "$signal" | jq -r '.id')
    CATEGORY=$(echo "$signal" | jq -r '.category')
    SEVERITY=$(echo "$signal" | jq -r '.severity')
    AFFECTED=$(echo "$signal" | jq -r '.evidence.affected_count')
    TOTAL=$(echo "$signal" | jq -r '.evidence.total')

    # Skip if already implemented
    if echo "$IMPLEMENTED_SIGS" | grep -qw "$SIG_ID" 2>/dev/null; then
        echo "Skipping $SIG_ID — already implemented"
        continue
    fi

    # Check if we have metadata for this signal
    HAS_META=$(echo "$SIGNAL_METADATA" | jq -e --arg id "$SIG_ID" '.[$id] // empty' > /dev/null 2>&1 && echo "yes" || echo "no")
    if [[ "$HAS_META" == "no" ]]; then
        echo "WARNING: No metadata for signal $SIG_ID — skipping" >&2
        continue
    fi

    # Extract metadata
    COMPLEXITY=$(echo "$SIGNAL_METADATA" | jq -r --arg id "$SIG_ID" '.[$id].complexity')
    BLAST=$(echo "$SIGNAL_METADATA" | jq -r --arg id "$SIG_ID" '.[$id].blast')

    # severity_multiplier
    case "$SEVERITY" in
        high)   SEV_MULT="0.9" ;;
        medium) SEV_MULT="0.6" ;;
        *)      SEV_MULT="0.3" ;;
    esac

    # complexity_factor
    case "$COMPLEXITY" in
        low)    COMPLEXITY_F="0.95" ;;
        medium) COMPLEXITY_F="0.7"  ;;
        high)   COMPLEXITY_F="0.4"  ;;
        *)      COMPLEXITY_F="0.7"  ;;
    esac

    # blast_radius_factor
    case "$BLAST" in
        function) BLAST_F="0.95" ;;
        file)     BLAST_F="0.8"  ;;
        multi)    BLAST_F="0.6"  ;;
        *)        BLAST_F="0.8"  ;;
    esac

    # category_weight
    case "$CATEGORY" in
        data_quality)       CAT_W="1.0" ;;
        trace_completeness) CAT_W="0.9" ;;
        *)                  CAT_W="0.8" ;;
    esac

    # priority = (affected/total × sev) × (complexity × blast) × cat_weight
    PRIORITY=$(jq -n \
        --argjson affected "$AFFECTED" \
        --argjson total "$TOTAL" \
        --argjson sev "$SEV_MULT" \
        --argjson comp "$COMPLEXITY_F" \
        --argjson blast "$BLAST_F" \
        --argjson catw "$CAT_W" \
        '(($affected / $total) * $sev) * ($comp * $blast) * $catw | . * 1000 | round / 1000')

    SCORE_LIST="${SCORE_LIST}${PRIORITY}|${SIG_ID}"$'\n'
done < <(jq -c '.improvement_signals[]' "$CACHE_FILE" 2>/dev/null)

if [[ -z "$SCORE_LIST" ]]; then
    echo "No signals to suggest (all implemented or none detected)"
    exit 0
fi

# --- Sort by priority descending ---
SORTED=$(printf '%s' "$SCORE_LIST" | sort -t'|' -k1 -rn | grep -v '^$')

# --- Write SUG-NNN.json files ---
SUG_NUM=1
while IFS='|' read -r PRIORITY SIG_ID; do
    [[ -z "$SIG_ID" ]] && continue

    # Get signal data from cache
    SIGNAL=$(jq -c --arg id "$SIG_ID" '.improvement_signals[] | select(.id == $id)' "$CACHE_FILE")
    AFFECTED=$(echo "$SIGNAL" | jq -r '.evidence.affected_count')
    TOTAL=$(echo "$SIGNAL" | jq -r '.evidence.total')
    SEVERITY=$(echo "$SIGNAL" | jq -r '.severity')

    # Get metadata
    TITLE=$(echo "$SIGNAL_METADATA" | jq -r --arg id "$SIG_ID" '.[$id].title')
    DESC=$(echo "$SIGNAL_METADATA" | jq -r --arg id "$SIG_ID" '.[$id].desc')
    FILES=$(echo "$SIGNAL_METADATA" | jq -c --arg id "$SIG_ID" '.[$id].files')
    APPROACH=$(echo "$SIGNAL_METADATA" | jq -r --arg id "$SIG_ID" '.[$id].approach')
    TEST_STRAT=$(echo "$SIGNAL_METADATA" | jq -r --arg id "$SIG_ID" '.[$id].test')

    SUG_ID=$(printf "SUG-%03d" "$SUG_NUM")
    SUG_FILE="${SUGGESTIONS_DIR}/${SUG_ID}.json"

    SCOPE_PCT=$(jq -n "($AFFECTED / $TOTAL * 100) | round | tostring" 2>/dev/null || echo "?")

    jq -cn \
        --arg id "$SUG_ID" \
        --arg signal_id "$SIG_ID" \
        --arg title "$TITLE" \
        --arg description "$DESC" \
        --argjson affected "$AFFECTED" \
        --argjson total "$TOTAL" \
        --arg scope_pct "$SCOPE_PCT" \
        --arg severity "$SEVERITY" \
        --argjson files "$FILES" \
        --arg approach "$APPROACH" \
        --arg test_strategy "$TEST_STRAT" \
        --argjson priority "$PRIORITY" \
        '{
          id: $id,
          status: "proposed",
          signal_id: $signal_id,
          title: $title,
          description: $description,
          impact: {
            scope: ($affected | tostring) + " of " + ($total | tostring) + " traces (" + $scope_pct + "%)",
            severity: $severity,
            enables: ["accurate trace analysis", "better observatory signal quality"]
          },
          implementation: {
            files_to_modify: $files,
            approach: $approach,
            test_strategy: $test_strategy
          },
          priority_score: $priority
        }' > "$SUG_FILE"

    echo "Created $SUG_ID → $SIG_ID (priority: $PRIORITY)"
    SUG_NUM=$((SUG_NUM + 1))
done <<< "$SORTED"

echo "Suggestion generation complete: $((SUG_NUM - 1)) suggestions in $SUGGESTIONS_DIR"
