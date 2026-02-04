# Future Considerations

Patterns evaluated during the SOTA assessment that were deferred. These may warrant
future work as projects scale or requirements evolve.

---

## Parallel Agent Orchestration

**What it is**: Running multiple agents concurrently (e.g., Implementer on Phase 1
while Planner works on Phase 2 design).

**Why it was skipped**:
- Current worktree model enables parallel *development* without parallel *agents*
- Sequential agent dispatch is simpler to reason about
- Lower risk of agents conflicting or duplicating work

**When to reconsider**:
- Large projects with 5+ independent phases
- Teams wanting multiple humans + agents working simultaneously
- Projects where planning and implementation have minimal overlap

**Implementation approach** (if needed):
1. Agent registry tracking active agents and their worktree assignments
2. Lock mechanism preventing two agents from modifying same files
3. Orchestrator awareness of parallel agent state
4. Merge conflict detection before agents complete

**Complexity**: High. Requires coordination layer that doesn't currently exist.

---

## Meta-Agent (Agent Builder)

**What it is**: An agent that can define and spawn new specialized agents based on
project requirements (e.g., "Create a DatabaseAgent for this project").

**Why it was skipped**:
- Current 3-agent system (Planner, Implementer, Guardian) covers most workflows
- Adding agents increases system complexity
- Risk of agent proliferation without clear boundaries

**When to reconsider**:
- Recurring domain-specific patterns (e.g., always need a "migration agent")
- Projects with unique workflows not covered by existing agents
- Power users who want to extend the system

**Implementation approach** (if needed):
1. Agent template system in `agents/templates/`
2. Meta-agent reads project context, proposes new agent definition
3. User approves agent definition before it becomes active
4. New agents follow same hook/validation patterns as built-in agents

**Complexity**: Medium. Mostly authoring new agent definitions, not new infrastructure.

---

## Enhanced Error Recovery

**What it is**: A ToolError hook that fires when tool calls fail, providing
contextual recovery suggestions.

**Why it was skipped**:
- Claude Code API may not currently support ToolError hooks
- Unclear hook contract for error events

**When to reconsider**:
- If Claude Code adds ToolError hook support
- High frequency of recoverable errors (git state issues, missing dirs)

**Implementation approach** (if needed):
1. Hook receives: tool name, error message, tool input
2. Pattern match common errors:
   - "directory not found" → suggest `mkdir -p`
   - "uncommitted changes" → suggest `git stash` or commit
   - "merge conflict" → suggest resolution workflow
3. Inject suggestion via additionalContext

**Complexity**: Low (if API supports it). Just pattern matching.

---

## RAG / Persistent Memory

**What it is**: Vector database or semantic search over past sessions, decisions,
and codebase for retrieval-augmented generation.

**Why it was skipped**:
- @decision system embeds knowledge in code (durable, versioned)
- research-log.md provides session continuity for research
- External RAG adds infrastructure complexity
- Risk of retrieving stale or irrelevant context

**When to reconsider**:
- Massive codebases where grep/ripgrep is too slow
- Need to query across multiple projects
- Historical decision archaeology (why did we do X 6 months ago?)

**Implementation approach** (if needed):
1. Index @decision annotations into vector DB at commit time
2. Index MASTER_PLAN.md history
3. Query interface for "find decisions related to X"
4. Surface as MCP tool or skill

**Complexity**: High. Requires external infrastructure (vector DB, embeddings).

**Alternative**: Improve @decision surfacing with better grep patterns and
the existing surface.sh pipeline. Often sufficient.

---

## AI Agent Hooks (Rejected)

**What it is**: Using AI models inside hooks instead of deterministic shell scripts.

**Why it was permanently rejected** (not just deferred):
- Non-deterministic runtime (seconds to minutes)
- Token consumption on every tool call
- Cascade risk (hook calls model, model calls tool, triggers hook...)
- Commits 4d34490 and 63af1ca documented failures

**This will NOT be reconsidered**. The deterministic hook model is a core design decision.

If AI judgment is needed, it should be:
1. A skill (invoked explicitly)
2. A SubagentStop validator (runs after agent completes, not during)
3. A Stop hook (runs at session end, after all tools)

Never: A PreToolUse or PostToolUse hook that calls an AI model.

---

## Auto-Approval Hooks (Rejected)

**What it is**: Hooks that automatically approve certain operations without user input.

**Why it was permanently rejected**:
- Violates Sacred Practice #8 (approval gates are intentional)
- Reduces user awareness of what's happening
- Risk of runaway automation

**This will NOT be reconsidered**. Human-in-the-loop for permanent operations is
a core design principle.

Acceptable automation:
- Linting (auto-fix with feedback loop)
- Test running (background, advisory)
- Context injection (informational)

Not acceptable:
- Auto-commit
- Auto-merge
- Auto-approve any Guardian operation

---

## Hook Refactoring: Shared Library Consolidation

**What it is**: Eliminate duplicate logic across hooks by consolidating into `context-lib.sh` shared functions, and standardize all hooks to use `get_field()` instead of raw `jq`.

**Why it was deferred**:
- System is functional today — no runtime failures
- Requires coordinated changes across 10+ hook files
- Best done in a worktree with test verification

**Identified issues (assessed 2026-02-04)**:

### High-Value: Session Lookup Consolidation

Session file lookup logic exists in **4 places** with varying robustness:

| Location | Glob fallback | Legacy `.session-decisions` | Status |
|----------|:---:|:---:|--------|
| `compact-preserve.sh` (lines 43-56) | Yes | Yes | Most robust |
| `surface.sh` (lines 29-41) | Yes | Yes | Nearly identical to compact-preserve |
| `session-summary.sh` (lines 26-32) | No | No | Simpler variant |
| `context-lib.sh` `get_session_changes()` (lines 78-93) | No | No | **Weakest — shared library version** |

The shared library version is the *weakest* implementation. The inline copies have already evolved beyond it.

**Fix**: Port glob/legacy fallback into `context-lib.sh`'s `get_session_changes()`, then replace all inline implementations with calls to the shared function.

### High-Value: `compact-preserve.sh` → Source `context-lib.sh`

`compact-preserve.sh` is the **only hook** that reimplements context-lib-equivalent operations (git state, plan parsing, session lookup) instead of sourcing the shared library. Three blocks of inline code duplicate shared functions with different variable names.

**Fix**: Add `source context-lib.sh`, replace inline blocks with `get_git_state()`, `get_plan_status()`, `get_session_changes()`. Keep `COMMIT_COUNT` as a one-liner supplement (not in shared lib).

### Medium-Value: `session-summary.sh` Hardcodes `SOURCE_EXTENSIONS`

Line 44 hardcodes the extension list that `context-lib.sh` exports as `$SOURCE_EXTENSIONS`. The hook already sources `context-lib.sh` but doesn't use the variable.

**Fix**: Replace hardcoded string with `$SOURCE_EXTENSIONS` reference.

### Low-Value: Raw `jq` Instead of `get_field()` (Systemic)

9 of 16 hooks use raw `echo "$HOOK_INPUT" | jq -r ...` instead of the `get_field()` helper from `log.sh`. Only 7 hooks use `get_field()` consistently. Affected hooks: `code-review.sh`, `plan-validate.sh`, `test-runner.sh`, `plan-check.sh` (partially), `notify.sh`, `forward-motion.sh`, `subagent-start.sh`, `surface.sh`, `session-summary.sh`, `prompt-submit.sh`.

**Fix**: Mechanical replacement. Zero behavioral change today.

### Cosmetic: `context-lib.sh` File Permissions

644 instead of 755. All other `.sh` files are 755. Works fine (sourced, not executed) but inconsistent.

**Fix**: `chmod +x hooks/context-lib.sh`

### Informational: `session-end.sh` Bypasses `read_input`

Reads stdin directly via `jq -r '.reason // "unknown"'` instead of using `read_input`/`get_field()`. Intentional performance optimization for large session histories. Document as a known exception, not a bug.

**When to tackle**:
- Next time hooks are being modified (natural opportunity)
- Before adding new shared library functions (ensures all consumers benefit)

**Implementation approach**:
1. Create worktree
2. Port robust session lookup into `context-lib.sh`
3. Refactor `compact-preserve.sh` to source `context-lib.sh`
4. Fix `session-summary.sh` SOURCE_EXTENSIONS reference
5. Batch convert raw `jq` → `get_field()` across all hooks
6. `chmod +x context-lib.sh`
7. Verify all hooks still pass (test with sample JSON inputs)

**Complexity**: Low-Medium. All changes are mechanical refactoring with no behavioral changes.

---

## Summary

| Pattern | Status | Revisit Trigger |
|---------|--------|-----------------|
| Parallel Agent Orchestration | Deferred | 5+ phase projects, team scaling |
| Meta-Agent | Deferred | Recurring domain-specific needs |
| Error Recovery Hook | Blocked | API support needed |
| RAG / Persistent Memory | Deferred | Massive codebase, cross-project queries |
| Hook Refactoring: Shared Lib Consolidation | Deferred | Next hook modification or new shared function |
| AI Agent Hooks | **Rejected** | Never |
| Auto-Approval | **Rejected** | Never |
