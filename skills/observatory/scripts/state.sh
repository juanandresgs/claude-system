#!/usr/bin/env bash
# state.sh — Observatory state CRUD library
#
# Purpose: Manage persistent observatory state (state.json + history.jsonl).
#          Provides init_state, get_pending, transition, defer_with_context,
#          get_reassessable, auto_resurface, and log_action functions used by
#          analyze.sh, suggest.sh, report.sh, and SKILL.md workflow.
#
# @decision DEC-OBS-005
# @title Sourceable library pattern for state management
# @status accepted
# @rationale state.sh is designed to be sourced (not executed) by other scripts.
#             This avoids subprocess overhead and lets callers share shell state.
#             Functions use OBS_DIR/STATE_FILE/HISTORY_FILE env vars so callers
#             can override paths for testing (DEC-OBS-003 isolation approach).
#
# @decision DEC-OBS-011
# @title State schema v3 — structured implemented objects for cohort regression
# @status accepted
# @rationale v1 implemented was a plain string array (["SUG-001", ...]) which
#             carried no timestamp or signal metadata. v2 added structured deferred
#             objects. v3 extends implemented to object array with sug_id, signal_id,
#             and implemented_at timestamp. This enables cohort-based regression
#             detection in analyze.sh: filter traces created after implemented_at
#             and re-evaluate the signal's evidence gate against that cohort.
#             Backwards compatibility: _migrate_state handles v1 string arrays for
#             implemented. During migration, signal_ids are resolved from a hardcoded
#             known-map of original SUG-NNN→signal_id assignments. This is required
#             because SUG files are renumbered on every suggest.sh run (DEC-OBS-022),
#             making the file-based lookup unreliable. Entries not in the known-map
#             get signal_id: null (manual cleanup needed). All migrated entries get
#             sug_id with -legacy suffix to distinguish from future v3-native entries.
#             v1 deferred was also a plain string array. v2/v3 uses object array with
#             sug_id, signal_id, deferred_at, reason, reassess_after,
#             reassess_condition, and priority_at_deferral. Migration from
#             v1->v3 converts both arrays to structured objects.
#
# @decision DEC-OBS-022
# @title SUG-ID instability — track by signal_id, not SUG-NNN
# @status accepted
# @rationale suggest.sh re-numbers SUG-NNN files on every run by priority order.
#             When new signals are detected or priorities shift, SUG-001 may map
#             to a different signal than before. Tracking implemented state by the
#             stable signal_id (e.g. SIG-TEST-UNKNOWN) rather than the ephemeral
#             SUG-NNN avoids silent skip failures. The migration in _migrate_state
#             resolves historical SUG-NNN→signal_id via a hardcoded known-map,
#             and future transition() calls record signal_id from the SUG file at
#             implementation time. suggest.sh skip logic reads signal_id directly
#             from state objects — no SUG-file indirection needed.
#
# @decision DEC-OBS-012
# @title auto_resurface uses date comparison, not cron
# @status accepted
# @rationale Reassessment is triggered when analyze.sh runs (opportunistic),
#             not on a schedule. date -u comparison converts ISO8601 to epoch
#             for arithmetic. Items past their reassess_after date move from
#             deferred back to proposed by resetting their SUG-NNN.json status.
#
# Usage: source skills/observatory/scripts/state.sh
#        init_state
#        transition "SUG-001" "proposed" "title" "0.855"
#        defer_with_context "SUG-001" "SIG-DURATION-BUG" "user" 7 "after SIG-TEST-UNKNOWN is implemented" "0.812"
#        log_action "analyzed" '{"trace_count": 320}'

set -euo pipefail

# --- Configuration (override via env for testing) ---
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
OBS_DIR="${OBS_DIR:-${CLAUDE_DIR}/observatory}"
STATE_FILE="${STATE_FILE:-${OBS_DIR}/state.json}"
HISTORY_FILE="${HISTORY_FILE:-${OBS_DIR}/history.jsonl}"
SUGGESTIONS_DIR="${SUGGESTIONS_DIR:-${OBS_DIR}/suggestions}"

# --- _compute_future_date ---
# Internal: compute a future ISO8601 date N days from now.
# Output: ISO8601 UTC timestamp string
_compute_future_date() {
    local days="${1:-7}"
    # macOS date syntax first, then GNU date fallback
    date -u -v "+${days}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -d "+${days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# --- _migrate_state ---
# Internal: migrate state.json from v1/v2 to v3 schema in-place.
# v1 deferred:     ["SUG-001", ...] (plain strings)
# v3 deferred:     [{ sug_id, signal_id, deferred_at, reason, reassess_after, ... }]
# v1 implemented:  ["SUG-001", ...] (plain strings)
# v3 implemented:  [{ sug_id, signal_id, implemented_at }]
#
# For v1 implemented entries, signal_ids are resolved from a hardcoded known-map
# of the original SUG-NNN → signal_id assignments (DEC-OBS-022). SUG files are
# unreliable for this because suggest.sh renumbers them on every run. Entries not
# in the known-map receive signal_id: null. All migrated sug_ids get a -legacy
# suffix so they can be distinguished from v3-native entries going forward.
#
# Approximate timestamps are set for known v1 entries (two batches from the
# original flywheel implementation — see DEC-OBS-022). These are intentionally
# approximate; exact times are not needed since cohort regression only needs
# a baseline date to filter post-implementation traces.
_migrate_state() {
    local version
    version=$(jq -r '.version // 1' "$STATE_FILE" 2>/dev/null || echo "1")

    if [[ "$version" -lt 3 ]]; then
        local tmp="${STATE_FILE}.tmp"
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local reassess_ts
        reassess_ts=$(_compute_future_date 7)

        # Hardcoded known v1 SUG-ID → signal_id map (DEC-OBS-022).
        # SUG-003 (SIG-DURATION-BUG) is included for completeness even if not in v1 state —
        # the jq lookup returns null for unknown keys so it's safe to include extra entries.
        # macOS bash 3.2: no declare -A, so we use a jq JSON object as the map.
        local KNOWN_V1_MAP
        KNOWN_V1_MAP='{"SUG-001":"SIG-TEST-UNKNOWN","SUG-002":"SIG-FILES-ZERO","SUG-003":"SIG-DURATION-BUG","SUG-004":"SIG-AGENT-TYPE-MISMATCH","SUG-005":"SIG-BRANCH-UNKNOWN","SUG-006":"SIG-STALE-MARKERS"}'

        # Approximate timestamps for the two original implementation batches.
        # Batch 1 (SUG-001, SUG-002): first observatory implementation pass.
        # Batch 2 (SUG-004, SUG-005, SUG-006): second implementation pass.
        # SUG-003 was never in v1 state (not implemented), but map entry is harmless.
        local IMPL_TS
        IMPL_TS="2026-02-18T03:00:00Z"

        jq --arg now "$now" \
           --arg reassess "$reassess_ts" \
           --argjson known_v1_map "$KNOWN_V1_MAP" \
           --arg impl_ts "$IMPL_TS" \
           '
           .version = 3 |
           # Migrate deferred: strings → objects
           if (.deferred | length) > 0 and (.deferred[0] | type) == "string" then
             .deferred = [.deferred[] | {
               sug_id: .,
               signal_id: null,
               deferred_at: $now,
               reason: "migrated_from_v1",
               reassess_after: $reassess,
               reassess_condition: null,
               priority_at_deferral: null
             }]
           else
             .deferred = (.deferred // [])
           end |
           # Migrate implemented: strings → objects
           # - sug_id gets "-legacy" suffix to distinguish from v3-native entries
           # - signal_id resolved from hardcoded known-map (null if not found)
           # - implemented_at set to approximate batch timestamp (not null)
           if (.implemented | length) > 0 and (.implemented[0] | type) == "string" then
             .implemented = [.implemented[] | {
               sug_id: (. + "-legacy"),
               signal_id: ($known_v1_map[.] // null),
               implemented_at: $impl_ts
             }]
           else
             .implemented = (.implemented // [])
           end
           ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    fi
}

# --- init_state ---
# Create observatory/state.json with empty v2 initial state if it does not exist.
# Idempotent: safe to call multiple times. Migrates v1 to v2 on existing files.
init_state() {
    mkdir -p "$OBS_DIR"
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << 'EOF'
{
  "version": 3,
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
    else
        # Migrate if needed (v1/v2 -> v3)
        _migrate_state
    fi
}

# --- get_pending ---
# Return the pending suggestion ID, or "null" if none.
# Output: suggestion ID string (e.g. "SUG-001") or "null"
get_pending() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "null"
        return
    fi
    jq -r '.pending_suggestion // "null"' "$STATE_FILE" 2>/dev/null || echo "null"
}

# --- transition ---
# Move a suggestion to a new status and update state.json accordingly.
# Usage: transition "SUG-001" "proposed|accepted|implemented|rejected|deferred" "title" "priority"
# - proposed:    sets pending_suggestion
# - accepted:    sets pending_suggestion (user approved — awaiting implementation)
# - implemented: clears pending, adds to implemented list
# - rejected:    clears pending, adds to rejected list
# - deferred:    clears pending, adds to deferred list (use defer_with_context for rich metadata)
transition() {
    local sug_id="$1"
    local new_status="$2"
    local title="${3:-}"
    local priority="${4:-null}"

    init_state

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp
    tmp="${STATE_FILE}.tmp"

    case "$new_status" in
        proposed|accepted)
            jq --arg id "$sug_id" \
               --arg title "$title" \
               --argjson priority "$priority" \
               '.pending_suggestion = $id | .pending_title = $title | .pending_priority = $priority' \
               "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            log_action "suggested" "{\"id\": \"$sug_id\", \"status\": \"$new_status\", \"priority\": $priority}"
            ;;
        implemented)
            # Look up signal_id from the suggestion file (if it exists)
            local signal_id="null"
            local sug_file="${SUGGESTIONS_DIR}/${sug_id}.json"
            if [[ -f "$sug_file" ]]; then
                signal_id=$(jq -r '.signal_id // "null"' "$sug_file" 2>/dev/null || echo "null")
                [[ "$signal_id" == "null" || -z "$signal_id" ]] && signal_id="null"
            fi
            local impl_ts
            impl_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

            jq --arg id "$sug_id" \
               --arg signal_id "$signal_id" \
               --arg impl_ts "$impl_ts" \
               '.pending_suggestion = null | .pending_title = null | .pending_priority = null
                | .implemented = (
                    # Remove any existing entry for this sug_id (dedup by sug_id)
                    [.implemented[] | select(
                      if type == "object" then .sug_id != $id else . != $id end
                    )] +
                    [{
                      sug_id: $id,
                      signal_id: (if $signal_id == "null" then null else $signal_id end),
                      implemented_at: $impl_ts
                    }]
                  )' \
               "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            log_action "implemented" "{\"id\": \"$sug_id\", \"signal_id\": \"$signal_id\"}"
            ;;
        rejected)
            jq --arg id "$sug_id" \
               '.pending_suggestion = null | .pending_title = null | .pending_priority = null
                | .rejected = (.rejected + [$id] | unique)' \
               "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            log_action "rejected" "{\"id\": \"$sug_id\"}"
            ;;
        deferred)
            # Simple defer with default 7-day reassessment window
            local now reassess_ts
            now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            reassess_ts=$(_compute_future_date 7)
            jq --arg id "$sug_id" \
               --arg now "$now" \
               --arg reassess "$reassess_ts" \
               --argjson priority "$priority" \
               '.pending_suggestion = null | .pending_title = null | .pending_priority = null
                | .deferred = (.deferred + [{
                    sug_id: $id,
                    signal_id: null,
                    deferred_at: $now,
                    reason: "user",
                    reassess_after: $reassess,
                    reassess_condition: null,
                    priority_at_deferral: $priority
                  }])' \
               "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            log_action "deferred" "{\"id\": \"$sug_id\"}"
            ;;
        *)
            echo "ERROR: Unknown status '$new_status'. Valid: proposed, accepted, implemented, rejected, deferred" >&2
            return 1
            ;;
    esac
}

# --- defer_with_context ---
# Defer a suggestion with rich reassessment metadata (v2 schema).
# Usage: defer_with_context SUG_ID SIGNAL_ID REASON DAYS CONDITION PRIORITY
#   SUG_ID:    e.g. "SUG-003"
#   SIGNAL_ID: e.g. "SIG-OUTCOME-FLAT" (or "null")
#   REASON:    "user" | "dependency" | "out_of_scope"
#   DAYS:      integer — reassess after N days (default 7)
#   CONDITION: human-readable reassessment condition (or "null")
#   PRIORITY:  priority score at time of deferral (numeric string, or "null")
defer_with_context() {
    local sug_id="${1}"
    local signal_id="${2:-null}"
    local reason="${3:-user}"
    local days="${4:-7}"
    local condition="${5:-null}"
    local priority="${6:-null}"

    init_state

    local now reassess_ts
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    reassess_ts=$(_compute_future_date "$days")

    local tmp="${STATE_FILE}.tmp"

    jq --arg sug_id "$sug_id" \
       --arg signal_id "$signal_id" \
       --arg now "$now" \
       --arg reason "$reason" \
       --arg reassess "$reassess_ts" \
       --arg condition "$condition" \
       --arg priority_str "$priority" \
       '
       .pending_suggestion = null | .pending_title = null | .pending_priority = null |
       .deferred = (.deferred + [{
         sug_id: $sug_id,
         signal_id: (if $signal_id == "null" or $signal_id == "" then null else $signal_id end),
         deferred_at: $now,
         reason: $reason,
         reassess_after: $reassess,
         reassess_condition: (if $condition == "null" or $condition == "" then null else $condition end),
         priority_at_deferral: (if $priority_str == "null" or $priority_str == "" then null else ($priority_str | tonumber) end)
       }])
       ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

    log_action "deferred_with_context" \
        "{\"id\": \"$sug_id\", \"signal_id\": \"$signal_id\", \"days\": $days, \"reason\": \"$reason\"}"
}

# --- get_reassessable ---
# Return sug_ids of deferred items past their reassess_after date.
# Output: one sug_id per line (may be empty)
get_reassessable() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return
    fi

    local now_epoch
    now_epoch=$(date -u +%s)

    # Extract deferred items whose reassess_after timestamp is in the past.
    # We use jq string manipulation since jq's strptime/mktime support varies.
    # The reassess_after format is always %Y-%m-%dT%H:%M:%SZ — we pass now_epoch
    # in and let jq compare after converting the stored timestamp to epoch.
    jq -r --argjson now_epoch "$now_epoch" '
      .deferred[]? |
      select(.reassess_after != null) |
      select(
        (.reassess_after | split("T") | .[0] | split("-") | map(tonumber) | .[0] * 10000 + .[1] * 100 + .[2]) <=
        ($now_epoch | todate | split("T") | .[0] | split("-") | map(tonumber) | .[0] * 10000 + .[1] * 100 + .[2])
      ) |
      .sug_id
    ' "$STATE_FILE" 2>/dev/null || true
}

# --- auto_resurface ---
# Called by analyze.sh: move deferred items past their reassess_after back
# to "proposed" by resetting their SUG-NNN.json status file.
# Returns: count of resurfaced items (as last line of output)
auto_resurface() {
    local resurfaced=0
    mkdir -p "$SUGGESTIONS_DIR"

    while IFS= read -r sug_id; do
        [[ -z "$sug_id" ]] && continue
        local sug_file="${SUGGESTIONS_DIR}/${sug_id}.json"
        if [[ -f "$sug_file" ]]; then
            local tmp="${sug_file}.tmp"
            jq '.status = "proposed"' "$sug_file" > "$tmp" && mv "$tmp" "$sug_file"

            # Remove from deferred array in state
            local stmp="${STATE_FILE}.tmp"
            jq --arg id "$sug_id" '.deferred = [.deferred[] | select(.sug_id != $id)]' \
               "$STATE_FILE" > "$stmp" && mv "$stmp" "$STATE_FILE"

            log_action "resurfaced" "{\"id\": \"$sug_id\"}"
            echo "Resurfaced: $sug_id"
            resurfaced=$((resurfaced + 1))
        fi
    done < <(get_reassessable)

    return 0
}

# --- log_action ---
# Append an action record to history.jsonl.
# Usage: log_action "action_name" '{"key": "value"}'
# The extra JSON fields are merged into the history entry alongside ts and action.
log_action() {
    local action="$1"
    local extra_json="${2:-{\}}"

    mkdir -p "$OBS_DIR"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Merge ts+action with extra fields
    local entry
    entry=$(jq -cn \
        --arg ts "$ts" \
        --arg action "$action" \
        --argjson extra "$extra_json" \
        '{ts: $ts, action: $action} + $extra' 2>/dev/null) || \
        entry="{\"ts\":\"$ts\",\"action\":\"$action\"}"

    echo "$entry" >> "$HISTORY_FILE"
}

# --- update_analysis_meta ---
# Record that analysis ran, with trace count and signal count.
# Usage: update_analysis_meta 320 5
update_analysis_meta() {
    local trace_count="${1:-0}"
    local signal_count="${2:-0}"

    init_state
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp="${STATE_FILE}.tmp"
    jq --arg ts "$ts" \
       --argjson tc "$trace_count" \
       '.last_analysis_at = $ts | .last_analysis_trace_count = $tc' \
       "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

    log_action "analyzed" "{\"trace_count\": $trace_count, \"signals\": $signal_count}"
}

# If executed directly (not sourced), print usage
# BASH_SOURCE may be unset in some subshell contexts — guard with ${BASH_SOURCE[0]:-}
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    echo "Usage: source skills/observatory/scripts/state.sh"
    echo "Functions: init_state, get_pending, transition, defer_with_context, get_reassessable, auto_resurface, log_action, update_analysis_meta"
fi
