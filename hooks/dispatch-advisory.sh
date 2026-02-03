#!/usr/bin/env bash
set -euo pipefail

# Orchestrator dispatch advisory for Write/Edit operations.
# PreToolUse hook — matcher: Write|Edit
#
# DECISION: Advisory-only orchestrator bypass detection. Rationale: CLAUDE.md
# Dispatch Rules say the orchestrator must not write source code directly, but
# no hook enforced this. A hard deny isn't possible (can't reliably detect
# orchestrator vs subagent), so this emits additionalContext as a visible
# reminder. Combined with branch-guard + plan-check + doc-gate, this
# significantly raises the bar for accidental orchestrator writes. Status: accepted.
#
# Emits additionalContext (advisory, not deny) when a source file write appears
# to come from the orchestrator session. Uses the same exemptions as other
# hooks (.claude/, config, docs, tests, MASTER_PLAN.md).

source "$(dirname "$0")/log.sh"
source "$(dirname "$0")/context-lib.sh"

HOOK_INPUT=$(read_input)
FILE_PATH=$(get_field '.tool_input.file_path')

# Exit silently if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# Skip the .claude config directory (meta-infrastructure exception)
[[ "$FILE_PATH" =~ \.claude/ ]] && exit 0

# Skip MASTER_PLAN.md (orchestrator writes plans on main)
[[ "$(basename "$FILE_PATH")" == "MASTER_PLAN.md" ]] && exit 0

# Skip non-source files (uses shared SOURCE_EXTENSIONS from context-lib.sh)
is_source_file "$FILE_PATH" || exit 0

# Skip test files, config files, vendor directories
is_skippable_path "$FILE_PATH" && exit 0

# If we're inside a subagent, this advisory doesn't apply
# CLAUDE_AGENT_TYPE is set for subagents (implementer, planner, guardian)
if [[ -n "${CLAUDE_AGENT_TYPE:-}" ]]; then
    exit 0
fi

# Emit advisory reminder
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "Dispatch Rules reminder: You are writing source code directly. CLAUDE.md requires invoking the Implementer agent for source code changes (meta-infrastructure exception: ~/.claude/ files only). If this is intentional (e.g., quick fix approved by user), proceed. Otherwise, delegate to the Implementer."
  }
}
EOF

exit 0
