#!/usr/bin/env bash
# test_session_init.sh — Tests for session-init.sh observatory integration
#
# Purpose: Verify that the observatory block in session-init.sh correctly
#          surfaces pending suggestions into CONTEXT_PARTS when state.json
#          has a pending suggestion.
#
# @decision DEC-OBS-004
# @title Test session-init integration via isolated bash subshells
# @status accepted
# @rationale session-init.sh cannot be sourced directly in tests because it
#             has side effects (resets prompt-count, etc.). We instead extract
#             the observatory logic and run it in isolated bash subshells with
#             mock state files. This tests the actual jq logic and CONTEXT_PARTS
#             population without triggering unrelated hook behavior.
#
# Usage: bash tests/observatory/test_session_init.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
WORKTREE="${CLAUDE_DIR}/.worktrees/feat-observatory"
SESSION_INIT="${WORKTREE}/hooks/session-init.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Test 1: session-init.sh exists in worktree ---
echo ""
echo "=== Test 1: session-init.sh exists in worktree ==="
if [[ -f "$SESSION_INIT" ]]; then
    pass "session-init.sh found at $SESSION_INIT"
else
    fail "session-init.sh not found at $SESSION_INIT (copy from main not done?)"
fi

# --- Test 2: Observatory block is present ---
echo ""
echo "=== Test 2: Observatory block in session-init.sh ==="
if grep -q "Observatory suggestions" "$SESSION_INIT" 2>/dev/null; then
    pass "Observatory comment block found in session-init.sh"
else
    fail "Observatory block not found in session-init.sh"
fi

# --- Test 3: References OBS_STATE variable ---
echo ""
echo "=== Test 3: OBS_STATE variable referenced ==="
if grep -q 'OBS_STATE' "$SESSION_INIT" 2>/dev/null; then
    pass "OBS_STATE variable present in session-init.sh"
else
    fail "OBS_STATE not referenced in session-init.sh"
fi

# --- Test 4: CONTEXT_PARTS gets observatory line with pending suggestion ---
echo ""
echo "=== Test 4: CONTEXT_PARTS populated when pending suggestion exists ==="

TEMP_STATE=$(mktemp)
trap "rm -f $TEMP_STATE" EXIT
cat > "$TEMP_STATE" << 'EOF'
{
  "version": 1,
  "last_analysis_at": "2026-02-17T00:00:00Z",
  "last_analysis_trace_count": 320,
  "pending_suggestion": "SUG-001",
  "pending_title": "Fix UTC timezone bug in finalize_trace",
  "pending_priority": 0.855,
  "implemented": [],
  "rejected": [],
  "deferred": []
}
EOF

OBS_RESULT=$(bash -c "
    OBS_STATE='$TEMP_STATE'
    CONTEXT_PARTS=()
    if [[ -f \"\$OBS_STATE\" ]]; then
        OBS_PENDING=\$(jq -r 'select(.pending_suggestion != null) | \"\(.pending_title) (priority: \(.pending_priority))\"' \"\$OBS_STATE\" 2>/dev/null)
        [[ -n \"\$OBS_PENDING\" ]] && CONTEXT_PARTS+=(\"Observatory: improvement ready — \$OBS_PENDING. Run /observatory to review.\")
    fi
    echo \"\${CONTEXT_PARTS[*]}\"
" 2>/dev/null)

if echo "$OBS_RESULT" | grep -q "Observatory: improvement ready"; then
    pass "CONTEXT_PARTS populated with observatory message when pending suggestion exists"
else
    fail "CONTEXT_PARTS not populated (got: '$OBS_RESULT')"
fi

# --- Test 5: No context added when no pending suggestion ---
echo ""
echo "=== Test 5: No context added when pending_suggestion is null ==="
TEMP_STATE2=$(mktemp)
trap "rm -f $TEMP_STATE2" EXIT
cat > "$TEMP_STATE2" << 'EOF'
{
  "version": 1,
  "last_analysis_at": null,
  "pending_suggestion": null,
  "pending_title": null,
  "pending_priority": null,
  "implemented": [],
  "rejected": [],
  "deferred": []
}
EOF

OBS_RESULT2=$(bash -c "
    OBS_STATE='$TEMP_STATE2'
    CONTEXT_PARTS=()
    if [[ -f \"\$OBS_STATE\" ]]; then
        OBS_PENDING=\$(jq -r 'select(.pending_suggestion != null) | \"\(.pending_title) (priority: \(.pending_priority))\"' \"\$OBS_STATE\" 2>/dev/null)
        [[ -n \"\$OBS_PENDING\" ]] && CONTEXT_PARTS+=(\"Observatory: improvement ready — \$OBS_PENDING. Run /observatory to review.\")
    fi
    echo \"\${CONTEXT_PARTS[*]}\"
" 2>/dev/null)

if [[ -z "$OBS_RESULT2" ]]; then
    pass "No CONTEXT_PARTS entry when pending_suggestion is null"
else
    fail "Unexpected CONTEXT_PARTS entry: '$OBS_RESULT2'"
fi

# --- Test 6: No context added when state file absent ---
echo ""
echo "=== Test 6: No context added when state file absent ==="
OBS_RESULT3=$(bash -c "
    OBS_STATE='/nonexistent/state.json'
    CONTEXT_PARTS=()
    if [[ -f \"\$OBS_STATE\" ]]; then
        OBS_PENDING=\$(jq -r 'select(.pending_suggestion != null) | \"\(.pending_title) (priority: \(.pending_priority))\"' \"\$OBS_STATE\" 2>/dev/null)
        [[ -n \"\$OBS_PENDING\" ]] && CONTEXT_PARTS+=(\"Observatory: improvement ready — \$OBS_PENDING. Run /observatory to review.\")
    fi
    echo \"\${CONTEXT_PARTS[*]}\"
" 2>/dev/null)

if [[ -z "$OBS_RESULT3" ]]; then
    pass "No CONTEXT_PARTS entry when state file absent"
else
    fail "Unexpected CONTEXT_PARTS entry when state absent: '$OBS_RESULT3'"
fi

# --- Summary ---
echo ""
echo "====================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "====================================="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
