#!/usr/bin/env bash
# @decision DEC-DIAG-001
# @title Hook and state health check script
# @status accepted
# @rationale Provides a single command to validate the entire hook/state system,
# catching misconfigurations before they cause silent failures. Checks hook file
# integrity, shared library health, state file formats, settings consistency,
# MASTER_PLAN.md validity, and git health.

set -uo pipefail

# --- Configuration ---
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOKS_DIR="${CLAUDE_DIR}/hooks"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() { echo "[PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
warn() { echo "[WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
fail() { echo "[FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# --- Detect project root for state files ---
detect_project_root() {
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR}" ]]; then
        echo "$CLAUDE_PROJECT_DIR"
        return
    fi
    if [[ -d "$PWD" ]]; then
        local root
        root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
        if [[ -n "$root" && -d "$root" ]]; then
            echo "$root"
            return
        fi
    fi
    echo "${HOME:-/}"
}

PROJECT_ROOT=$(detect_project_root)

echo "=== Claude Code Hook & State Diagnostics ==="
echo "Config directory: $CLAUDE_DIR"
echo "Project root:    $PROJECT_ROOT"
echo ""

# ============================================================
# 1. Hook File Integrity
# ============================================================
echo "--- Hook File Integrity ---"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    fail "Settings file not found: $SETTINGS_FILE"
else
    # Extract all hook command paths from settings.json
    hook_commands=$(jq -r '
        .hooks // {} | to_entries[] | .value[] | .hooks[]? | .command // empty
    ' "$SETTINGS_FILE" 2>/dev/null)

    # Also check statusLine command
    status_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [[ -n "$status_cmd" ]]; then
        hook_commands="$hook_commands"$'\n'"$status_cmd"
    fi

    hook_total=0
    hook_found=0
    hook_missing=()
    hook_noexec=()

    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        # Expand $HOME and ~ in command paths
        expanded_cmd="${cmd//\$HOME/$HOME}"
        expanded_cmd="${expanded_cmd/#\~/$HOME}"

        # Extract the script path (first word of the command)
        script_path="${expanded_cmd%% *}"

        hook_total=$((hook_total + 1))

        if [[ ! -f "$script_path" ]]; then
            hook_missing+=("$cmd")
        elif [[ ! -x "$script_path" ]]; then
            hook_noexec+=("$cmd")
        else
            hook_found=$((hook_found + 1))
        fi
    done <<< "$hook_commands"

    if [[ ${#hook_missing[@]} -gt 0 ]]; then
        for h in "${hook_missing[@]}"; do
            fail "Hook script not found: $h"
        done
    fi

    if [[ ${#hook_noexec[@]} -gt 0 ]]; then
        for h in "${hook_noexec[@]}"; do
            fail "Hook script not executable: $h (run: chmod +x)"
        done
    fi

    if [[ ${#hook_missing[@]} -eq 0 && ${#hook_noexec[@]} -eq 0 ]]; then
        pass "Hook integrity: ${hook_found}/${hook_total} hooks found and executable"
    fi
fi
echo ""

# ============================================================
# 2. Shared Library Health
# ============================================================
echo "--- Shared Library Health ---"

for lib in "log.sh" "context-lib.sh"; do
    lib_path="$HOOKS_DIR/$lib"
    if [[ ! -f "$lib_path" ]]; then
        fail "Shared library missing: $lib_path"
    elif ! bash -n "$lib_path" 2>/dev/null; then
        fail "Shared library has syntax errors: $lib_path"
    else
        pass "Shared library OK: $lib"
    fi
done
echo ""

# ============================================================
# 3. State File Validation
# ============================================================
echo "--- State File Validation ---"

state_dir="$PROJECT_ROOT/.claude"

# .plan-drift
drift_file="$state_dir/.plan-drift"
if [[ -f "$drift_file" ]]; then
    has_unplanned=$(grep -c '^unplanned_count=' "$drift_file" 2>/dev/null || true)
    has_unimplemented=$(grep -c '^unimplemented_count=' "$drift_file" 2>/dev/null || true)
    if [[ "$has_unplanned" -gt 0 && "$has_unimplemented" -gt 0 ]]; then
        pass "State: .plan-drift has expected fields"
    else
        warn "State: .plan-drift exists but missing expected fields (unplanned_count, unimplemented_count)"
    fi
else
    pass "State: .plan-drift not present (normal if no drift audit has run)"
fi

# .agent-findings
findings_file="$state_dir/.agent-findings"
if [[ -f "$findings_file" ]]; then
    if jq empty "$findings_file" 2>/dev/null; then
        pass "State: .agent-findings is valid JSON"
    else
        fail "State: .agent-findings exists but is not valid JSON"
    fi
else
    pass "State: .agent-findings not present (normal)"
fi

# .proof-status
proof_file="$state_dir/.proof-status"
if [[ -f "$proof_file" ]]; then
    proof_content=$(cat "$proof_file" 2>/dev/null)
    if [[ "$proof_content" =~ ^verified\|[0-9]+$ ]] || [[ "$proof_content" == "unverified" ]] || [[ "$proof_content" =~ ^pending ]]; then
        # Check staleness
        if [[ "$proof_content" =~ ^verified\|([0-9]+)$ ]]; then
            proof_epoch="${BASH_REMATCH[1]}"
            now=$(date +%s)
            age_days=$(( (now - proof_epoch) / 86400 ))
            if [[ "$age_days" -gt 3 ]]; then
                warn "State: .proof-status is stale (last verified ${age_days} days ago)"
            else
                pass "State: .proof-status format valid (verified ${age_days}d ago)"
            fi
        else
            pass "State: .proof-status format valid ($proof_content)"
        fi
    else
        warn "State: .proof-status has unexpected format: $proof_content"
    fi
else
    pass "State: .proof-status not present (normal)"
fi

# .test-status
test_file="$state_dir/.test-status"
if [[ -f "$test_file" ]]; then
    test_content=$(cat "$test_file" 2>/dev/null)
    if [[ "$test_content" =~ ^(pass|fail)\|[0-9]+\|[0-9]+$ ]]; then
        pass "State: .test-status format valid"
    else
        warn "State: .test-status has unexpected format: $test_content"
    fi
else
    pass "State: .test-status not present (normal)"
fi
echo ""

# ============================================================
# 4. Settings Consistency
# ============================================================
echo "--- Settings Consistency ---"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Check for duplicate hook registrations within the same event
    events=$(jq -r '.hooks // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null)
    dup_found=false
    while IFS= read -r event; do
        [[ -z "$event" ]] && continue
        # Extract all command values for this event
        commands=$(jq -r ".hooks.\"$event\"[]?.hooks[]?.command // empty" "$SETTINGS_FILE" 2>/dev/null | sort)
        dupes=$(echo "$commands" | uniq -d)
        if [[ -n "$dupes" ]]; then
            while IFS= read -r d; do
                [[ -n "$d" ]] && fail "Duplicate hook in $event: $d"
            done <<< "$dupes"
            dup_found=true
        fi
    done <<< "$events"

    if [[ "$dup_found" == "false" ]]; then
        pass "Settings: no duplicate hook registrations"
    fi

    # Validate settings JSON structure
    if jq empty "$SETTINGS_FILE" 2>/dev/null; then
        pass "Settings: valid JSON"
    else
        fail "Settings: invalid JSON in $SETTINGS_FILE"
    fi
else
    fail "Settings: file not found at $SETTINGS_FILE"
fi
echo ""

# ============================================================
# 5. MASTER_PLAN.md Status
# ============================================================
echo "--- MASTER_PLAN.md Status ---"

plan_file="$PROJECT_ROOT/MASTER_PLAN.md"
if [[ -f "$plan_file" ]]; then
    # Check for original intent section
    if grep -qiE '^\#.*intent|^\#.*vision|^\#.*user.*request|^\#.*original' "$plan_file" 2>/dev/null; then
        pass "Plan: Original Intent section present"
    else
        warn "Plan: Missing Original Intent section"
    fi

    # Check phase statuses
    phase_issues=0
    phase_headers=$(grep -nE '^\#\#\s+Phase\s+[0-9]' "$plan_file" 2>/dev/null || echo "")
    if [[ -n "$phase_headers" ]]; then
        total_phases=$(echo "$phase_headers" | wc -l | tr -d ' ')
        completed=$(grep -cE '\*\*Status:\*\*\s*completed' "$plan_file" 2>/dev/null || true)
        in_progress=$(grep -cE '\*\*Status:\*\*\s*in-progress' "$plan_file" 2>/dev/null || true)
        planned=$(grep -cE '\*\*Status:\*\*\s*planned' "$plan_file" 2>/dev/null || true)

        # Check for invalid status values (macOS-compatible, no grep -P)
        all_statuses=$(grep -oE '\*\*Status:\*\*\s*[a-z-]+' "$plan_file" 2>/dev/null | sed 's/.*\*\*Status:\*\*[[:space:]]*//' || true)
        if [[ -n "$all_statuses" ]]; then
            while IFS= read -r status; do
                if [[ "$status" != "planned" && "$status" != "in-progress" && "$status" != "completed" ]]; then
                    fail "Plan: Invalid phase status '$status' (must be planned|in-progress|completed)"
                    phase_issues=$((phase_issues + 1))
                fi
            done <<< "$all_statuses"
        fi

        if [[ "$phase_issues" -eq 0 ]]; then
            pass "Plan: ${total_phases} phases (${completed:-0} completed, ${in_progress:-0} in-progress, ${planned:-0} planned)"
        fi
    else
        pass "Plan: No phases found (may be a simple plan)"
    fi

    # Check DEC-ID format
    dec_ids=$(grep -oE 'DEC-[A-Za-z]+-[0-9]+' "$plan_file" 2>/dev/null | sort -u || echo "")
    dec_issues=0
    if [[ -n "$dec_ids" ]]; then
        while IFS= read -r dec_id; do
            if ! echo "$dec_id" | grep -qE '^DEC-[A-Z]{2,}-[0-9]{3}$'; then
                warn "Plan: Decision ID '$dec_id' does not follow DEC-COMPONENT-NNN format"
                dec_issues=$((dec_issues + 1))
            fi
        done <<< "$dec_ids"
        total_decs=$(echo "$dec_ids" | wc -l | tr -d ' ')
        if [[ "$dec_issues" -eq 0 ]]; then
            pass "Plan: ${total_decs} DEC-IDs, all valid format"
        fi
    fi

    # Check REQ-ID format
    req_ids=$(grep -oE 'REQ-[A-Za-z0-9]+-[0-9]+' "$plan_file" 2>/dev/null | sort -u || echo "")
    req_issues=0
    if [[ -n "$req_ids" ]]; then
        while IFS= read -r req_id; do
            if ! echo "$req_id" | grep -qE '^REQ-(GOAL|NOGO|UJ|P0|P1|P2|MET)-[0-9]{3}$'; then
                warn "Plan: Requirement ID '$req_id' does not follow REQ-CATEGORY-NNN format"
                req_issues=$((req_issues + 1))
            fi
        done <<< "$req_ids"
        total_reqs=$(echo "$req_ids" | wc -l | tr -d ' ')
        if [[ "$req_issues" -eq 0 ]]; then
            pass "Plan: ${total_reqs} REQ-IDs, all valid format"
        fi
    fi
else
    pass "Plan: No MASTER_PLAN.md in project root (normal if not planning)"
fi
echo ""

# ============================================================
# 6. Git Health
# ============================================================
echo "--- Git Health ---"

if [[ -d "$PROJECT_ROOT/.git" ]] || git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # Orphaned worktrees
    worktree_output=$(git -C "$PROJECT_ROOT" worktree list --porcelain 2>/dev/null || echo "")
    if [[ -n "$worktree_output" ]]; then
        orphaned=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
                wt_path="${BASH_REMATCH[1]}"
                if [[ ! -d "$wt_path" ]]; then
                    warn "Git: Orphaned worktree reference: $wt_path (run: git worktree prune)"
                    orphaned=$((orphaned + 1))
                fi
            fi
        done <<< "$worktree_output"

        wt_count=$(git -C "$PROJECT_ROOT" worktree list 2>/dev/null | grep -v "(bare)" | tail -n +2 | wc -l | tr -d ' ')
        if [[ "$orphaned" -eq 0 ]]; then
            pass "Git: ${wt_count} worktrees, none orphaned"
        fi
    fi

    # Uncommitted changes
    dirty_count=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$dirty_count" -gt 0 ]]; then
        warn "Git: ${dirty_count} uncommitted changes in project root"
    else
        pass "Git: Working tree clean"
    fi

    # Current branch
    branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    pass "Git: On branch '$branch'"
else
    warn "Git: Project root is not a git repository"
fi
echo ""

# ============================================================
# Summary
# ============================================================
echo "=== Summary ==="
echo "PASS: $PASS_COUNT | WARN: $WARN_COUNT | FAIL: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo ""
    echo "Action required: $FAIL_COUNT critical issues found. See FAIL entries above."
    exit 1
elif [[ "$WARN_COUNT" -gt 0 ]]; then
    echo ""
    echo "System functional with $WARN_COUNT warnings. Review WARN entries above."
    exit 0
else
    echo ""
    echo "All checks passed. System is healthy."
    exit 0
fi
