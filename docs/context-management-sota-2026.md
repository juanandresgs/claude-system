# Context Management for LLM Coding Agents — SOTA 2026

Research compiled 2026-02-04. Synthesized from Anthropic engineering guidance, community practitioners, academic research, and cross-tool ecosystem patterns.

---

## 1. Structuring Instruction Files

### Three-Layer Architecture (Consensus)

| Layer | Content | Size | Loaded When |
|---|---|---|---|
| **Always-loaded** (CLAUDE.md root) | Project overview, essential commands, stack, pointers to deeper docs | 50-60 lines, ~500 tokens | Every session, every call |
| **On-demand docs** (e.g., `/docs/`, child CLAUDE.md files) | Gotchas, architectural decisions, edge cases, domain knowledge | 200-500 tokens per file | Agent reads when relevant |
| **Specialized agents/skills** (e.g., `.claude/agents/`, skills/) | Domain-specific workflows, complex procedures | 300-800 tokens per agent | Explicitly triggered via Task tool or subagent |

### Optimal Length

- Anthropic official: keep concise and human-readable, under ~500 lines
- HumanLayer tested recommendation: under 60 lines for root file
- Progressive disclosure finding: frontier models follow 150-200 instructions reliably; system prompt already consumes ~50
- Measured: reducing CLAUDE.md from 2,800 to 200 lines saved 62% of tokens (1,300 tokens/session)

### One File vs. Multiple Files

- **Monolithic**: everything always present, but instruction-following degrades as count rises; steals context from actual work
- **Split**: preserves context budget but requires explicit loading directive
- **Proven pattern**: lean root file with explicit pointers + directive telling agent to read relevant docs before starting

### Cross-Tool Convergence (AGENTS.md)

AGENTS.md adopted by 60,000+ open-source projects. Recognized by Codex, Gemini CLI, GitHub Copilot, Claude Code. GitHub analyzed 2,500 repos — top files address: commands, testing, project structure, code style, git workflow, boundaries/constraints.

### What to Include

1. Executable commands with flags (build, test, lint) — put these early
2. Tech stack with versions
3. File structure map
4. Three-tier boundary system: "Always do" / "Ask first" / "Never do"
5. Real code examples of preferred patterns
6. Pointers to deeper documentation

### What to Exclude

- Code style rules (delegate to linters)
- Vague directives ("write good code")
- Generic tech stack without versions
- Task-specific instructions for one workflow
- War stories or historical context

---

## 2. Context Window Management Strategies

Context is the primary constraint, not model intelligence. Goal: "the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome." Performance degrades nonlinearly past ~70% capacity.

### Ranked by Impact

**A. Observation masking (highest ROI).** JetBrains Research (Dec 2025): preserving full action/reasoning history while replacing older tool outputs with placeholders cut costs 52% while matching or exceeding summarization performance. With Qwen3-Coder 480B, masking improved solve rates by 2.6%.

**B. Proactive compaction at 70% capacity.** Treat 70% as practical ceiling. Last 20% (80-100%) provides "disproportionately poor value." Use `/compact` with focus instructions.

**C. Subagent/fork isolation.** Exploration consumes main context permanently. Run in subagent, receive summary back.

**D. Tool result clearing.** Old tool outputs rarely needed again. Truncate or clear.

**E. Plan-then-execute with session boundaries.** Write spec to file, start fresh session for implementation.

**F. MCP tool bloat awareness.** "If you're using more than 20k tokens of MCPs, you're crippling Claude."

---

## 3. Reference vs. Inline

### Cross-Tool Pattern

| Tool | Always-loaded | On-demand | Activation |
|---|---|---|---|
| **Claude Code** | Root + parent CLAUDE.md, ~/.claude/CLAUDE.md | Child CLAUDE.md, skills, referenced docs | Hierarchical auto-load + explicit read |
| **Cursor** | `.mdc` with `alwaysApply: true` | Glob-matched or model-decision `.mdc` | Always On / Glob / Model Decision / Manual |
| **Aider** | `--read` conventions file | `--file` task-specific | Explicit flags |
| **Windsurf** | Global rules (6000 char/rule, 12000 total) | Workspace rules, manual-activation | Always On / Model Decision / Manual |
| **AGENTS.md** | Root AGENTS.md | Subdirectory AGENTS.md | Hierarchical auto-load |

### Inline When

- Universal project facts: stack, versions, commands
- Behavioral boundaries: "always do X", "never do Y"
- Pointers to on-demand resources
- The directive to read relevant docs

### Reference When

- Domain-specific gotchas
- Architectural decision records
- Complex workflow procedures
- Component-specific conventions
- Historical learnings

### Critical Detail

Without an explicit instruction telling the agent to load on-demand docs, it won't. The directive must be prominent: "IMPORTANT: Before starting any task, identify which docs below are relevant and read them first."

---

## 4. Staleness and Drift Prevention

Least-solved problem in the ecosystem. No dominant automated solution. Emerging patterns:

**A. Code-is-truth.** Treat codebase as source of truth. Minimize external documentation surface area. @decision markers in code.

**B. Iterative growth.** GitHub analysis: "The best agent files grow through iteration, not upfront planning." Add detail only when agent demonstrably fails without it.

**C. /learn feedback loop.** Analyze conversation for reusable insights, propose placement in docs, await approval. Structured path from mistake to prevention.

**D. Hooks as deterministic enforcement.** "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens." Move deterministic rules out of instructions into hooks.

**E. Automated evals.** "Capability evals with high pass rates can graduate to become a regression suite run continuously to catch drift."

**F. Couple rule updates to discovery.** Update rules when you learn better ways, not on a schedule.

**G. Point to code, don't embed it.** Use file:line references instead of code snippets. Embedded snippets become stale.

---

## Actionable Recommendations

1. **Keep always-loaded file ruthlessly lean.** Target 50-60 lines. Every line competes with working context.
2. **Progressive disclosure with explicit loading directives.** Split domain knowledge. Prominent directive to read relevant docs.
3. **Delegate deterministic rules to hooks/linters.** Reduces instruction count and eliminates compliance variability.
4. **Compact proactively at 70%.** Focus-directed compaction preserving decisions, discarding tool noise.
5. **Subagent isolation for exploration.** Fork context for file-reading-heavy tasks.
6. **Grow through failure iteration.** Start minimal, add instructions only for demonstrated failures.
7. **Point to code, not embed.** file:line references over code snippets.
8. **Adopt AGENTS.md alongside tool-specific files.** Cross-tool compatibility (60k+ repos).

---

## Sources

- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Anthropic: Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Claude Code Docs: Best Practices](https://code.claude.com/docs/en/best-practices)
- [JetBrains Research: Efficient Context Management](https://blog.jetbrains.com/research/2025/12/efficient-context-management/)
- [GitHub Blog: How to Write a Great AGENTS.md](https://github.blog/ai-and-ml/github-copilot/how-to-write-a-great-agents-md-lessons-from-over-2500-repositories/)
- [HumanLayer: Writing a Good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
- [Stop Bloating Your CLAUDE.md: Progressive Disclosure](https://alexop.dev/posts/stop-bloating-your-claude-md-progressive-disclosure-ai-coding-tools/)
- [AGENTS.md Official Site](https://agents.md/)
- [AGENTS.md on InfoQ](https://www.infoq.com/news/2025/08/agents-md/)
- [Cursor Docs: Rules](https://cursor.com/docs/context/rules)
- [Aider: Specifying Coding Conventions](https://aider.chat/docs/usage/conventions.html)
- [Windsurf Rules & Workflows](https://www.paulmduvall.com/using-windsurf-rules-workflows-and-memories/)
- [Addy Osmani: My LLM Coding Workflow Going into 2026](https://addyosmani.com/blog/ai-coding-workflow/)
- [Anthropic: Equipping Agents with Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Claude Agent Skills Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
