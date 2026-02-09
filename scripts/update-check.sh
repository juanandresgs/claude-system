#!/usr/bin/env bash
# Harness auto-update checker
# SessionStart hook — matcher: startup (runs only on fresh session start)
#
# @decision DEC-UPDATE-001
# @title Git-based auto-update with semver gating
# @status accepted
# @rationale Auto-apply safe updates (same MAJOR version) to keep harness
#   current across devices. Notify-only for breaking changes (different MAJOR).
#   Abort cleanly on conflict. Silent skip on network failure. Uses
#   git pull --autostash --rebase for fork/customization safety.
#
# Flow:
#   0. Check disable toggle (.disable-auto-update)
#   1. Lock file to prevent concurrent checks
#   2. Fetch origin/main with timeout
#   3. Compare local vs remote HEAD
#   4. Compare MAJOR versions (semver)
#   5. Auto-apply (same MAJOR) or notify (different MAJOR)
#   6. Write .update-status for session-init.sh consumption
#
# Status file format: status|local_version|remote_version|commit_count|timestamp|summary
# Where status is: up-to-date, updated, breaking, conflict, error

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
STATUS_FILE="$CLAUDE_DIR/.update-status"
LOCK_FILE="$CLAUDE_DIR/.update-check.lock"
DISABLE_FILE="$CLAUDE_DIR/.disable-auto-update"
VERSION_FILE="$CLAUDE_DIR/VERSION"

# Always clean up lock file on exit
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

write_status() {
    local status="$1"
    local local_ver="${2:-}"
    local remote_ver="${3:-}"
    local count="${4:-0}"
    local summary="${5:-}"
    echo "${status}|${local_ver}|${remote_ver}|${count}|$(date +%s)|${summary}" > "$STATUS_FILE"
}

# --- Step 0: Disable toggle ---
if [[ -f "$DISABLE_FILE" ]]; then
    exit 0
fi

# --- Step 1: Lock file (prevent concurrent checks) ---
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
        # Another check is running
        exit 0
    fi
    # Stale lock — clean up
    rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"

# --- Verify we're in a git repo ---
if ! git -C "$CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# --- Step 2: Fetch origin/main with timeout ---
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=5

if ! git -C "$CLAUDE_DIR" fetch origin main --quiet 2>/dev/null; then
    # Network unavailable — silent skip
    exit 0
fi

# --- Step 3: Compare HEADs ---
LOCAL_HEAD=$(git -C "$CLAUDE_DIR" rev-parse HEAD 2>/dev/null || echo "")
REMOTE_HEAD=$(git -C "$CLAUDE_DIR" rev-parse origin/main 2>/dev/null || echo "")

if [[ -z "$LOCAL_HEAD" || -z "$REMOTE_HEAD" ]]; then
    exit 0
fi

if [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]]; then
    write_status "up-to-date"
    exit 0
fi

# --- Step 4: Version comparison ---
LOCAL_VERSION=""
REMOTE_VERSION=""

if [[ -f "$VERSION_FILE" ]]; then
    LOCAL_VERSION=$(head -1 "$VERSION_FILE" | tr -d '[:space:]')
fi

REMOTE_VERSION=$(git -C "$CLAUDE_DIR" show origin/main:VERSION 2>/dev/null | head -1 | tr -d '[:space:]' || echo "")

# Parse MAJOR version (first number before first dot)
LOCAL_MAJOR="${LOCAL_VERSION%%.*}"
REMOTE_MAJOR="${REMOTE_VERSION%%.*}"

# Default to 0 if empty
LOCAL_MAJOR="${LOCAL_MAJOR:-0}"
REMOTE_MAJOR="${REMOTE_MAJOR:-0}"

if [[ "$LOCAL_MAJOR" != "$REMOTE_MAJOR" ]]; then
    # Breaking change — notify only, do NOT pull
    write_status "breaking" "$LOCAL_VERSION" "$REMOTE_VERSION" "0" "MAJOR version change"
    exit 0
fi

# --- Step 5: Auto-apply (same MAJOR) ---
COMMIT_COUNT=$(git -C "$CLAUDE_DIR" rev-list HEAD..origin/main --count 2>/dev/null || echo "0")
COMMIT_SUMMARY=$(git -C "$CLAUDE_DIR" log HEAD..origin/main --oneline --no-decorate 2>/dev/null | head -5 || echo "")

if git -C "$CLAUDE_DIR" pull --autostash --rebase origin main --quiet 2>/dev/null; then
    # Success — read new version from potentially updated VERSION file
    NEW_VERSION=""
    if [[ -f "$VERSION_FILE" ]]; then
        NEW_VERSION=$(head -1 "$VERSION_FILE" | tr -d '[:space:]')
    fi
    write_status "updated" "$LOCAL_VERSION" "${NEW_VERSION:-$REMOTE_VERSION}" "$COMMIT_COUNT" "$COMMIT_SUMMARY"
else
    # Conflict — abort rebase, restore state
    git -C "$CLAUDE_DIR" rebase --abort 2>/dev/null || true
    write_status "conflict" "$LOCAL_VERSION" "$REMOTE_VERSION" "$COMMIT_COUNT" "merge conflict with local changes"
fi

exit 0
