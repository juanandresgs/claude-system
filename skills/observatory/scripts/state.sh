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
# @title State schema v2 — structured deferred objects
# @status accepted
# @rationale v1 deferred was a plain string array (["SUG-001", ...]) which
#             carried no reassessment metadata. v2 uses object array with
#             sug_id, signal_id, deferred_at, reason, reassess_after,
#             reassess_condition, and priority_at_deferral. Migration from
#             v1->v2 converts the string array to minimal objects with
#             reassess_after = deferred_at + 7 days. This preserves history
#             while enabling the new lifecycle functions.
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
# Internal: migrate state.json from v1 to v2 schema in-place.
# v1 deferred: ["SUG-001", ...]
# v2 deferred: [{ sug_id, signal_id, deferred_at, reason, reassess_after, ... }]
_migrate_state() {
    local version
    version=$(jq -r '.version // 1' "$STATE_FILE" 2>/dev/null || echo "1")

    if [[ "$version" -lt 2 ]]; then
        local tmp="${STATE_FILE}.tmp"
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local reassess_ts
        reassess_ts=$(_compute_future_date 7)

        jq --arg now "$now" \
           --arg reassess "$reassess_ts" \
           '
           .version = 2 |
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
             .version = 2 |
             .deferred = (.deferred // [])
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
  "version": 2,
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
        # Migrate if needed (v1 -> v2)
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
            jq --arg id "$sug_id" \
               '.pending_suggestion = null | .pending_title = null | .pending_priority = null
                | .implemented = (.implemented + [$id] | unique)' \
               "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            log_action "implemented" "{\"id\": \"$sug_id\"}"
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
