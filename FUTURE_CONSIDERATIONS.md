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

## Summary

| Pattern | Status | Revisit Trigger |
|---------|--------|-----------------|
| Parallel Agent Orchestration | Deferred | 5+ phase projects, team scaling |
| Meta-Agent | Deferred | Recurring domain-specific needs |
| Error Recovery Hook | Blocked | API support needed |
| RAG / Persistent Memory | Deferred | Massive codebase, cross-project queries |
| AI Agent Hooks | **Rejected** | Never |
| Auto-Approval | **Rejected** | Never |
