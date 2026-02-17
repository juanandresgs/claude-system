#!/usr/bin/env bash
# state.sh — Observatory state CRUD library
#
# Purpose: Manage persistent observatory state (state.json + history.jsonl).
#          Provides init_state, get_pending, transition, and log_action
#          functions used by analyze.sh, suggest.sh, and SKILL.md workflow.
#
# @decision DEC-OBS-005
# @title Sourceable library pattern for state management
# @status accepted
# @rationale state.sh is designed to be sourced (not executed) by other scripts.
#             This avoids subprocess overhead and lets callers share shell state.
#             Functions use OBS_DIR/STATE_FILE/HISTORY_FILE env vars so callers
#             can override paths for testing (DEC-OBS-003 isolation approach).
#
# Usage: source skills/observatory/scripts/state.sh
#        init_state
#        transition "SUG-001" "proposed" "title" "0.855"
#        log_action "analyzed" '{"trace_count": 320}'

set -euo pipefail

# --- Configuration (override via env for testing) ---
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
OBS_DIR="${OBS_DIR:-${CLAUDE_DIR}/observatory}"
STATE_FILE="${STATE_FILE:-${OBS_DIR}/state.json}"
HISTORY_FILE="${HISTORY_FILE:-${OBS_DIR}/history.jsonl}"

# --- init_state ---
# Create observatory/state.json with empty initial state if it doesn't exist.
# Idempotent: safe to call multiple times.
init_state() {
    mkdir -p "$OBS_DIR"
    if [[ ! -f "$STATE_FILE" ]]; then
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
# - deferred:    clears pending, adds to deferred list
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
            jq --arg id "$sug_id" \
               '.pending_suggestion = null | .pending_title = null | .pending_priority = null
                | .deferred = (.deferred + [$id] | unique)' \
               "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
            log_action "deferred" "{\"id\": \"$sug_id\"}"
            ;;
        *)
            echo "ERROR: Unknown status '$new_status'. Valid: proposed, accepted, implemented, rejected, deferred" >&2
            return 1
            ;;
    esac
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
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Usage: source skills/observatory/scripts/state.sh"
    echo "Functions: init_state, get_pending, transition, log_action, update_analysis_meta"
fi
