# Architecture: Claude Code Configuration System

**@decision DEC-ARCH-001**
**@title Architectural overview document for system structure and data flow**
**@status accepted**
**@rationale** Provides a standalone reference for understanding system components,
hook execution model, and key design decisions. Complements README.md (user guide)
and HOOKS.md (protocol reference) by explaining HOW the pieces fit together and WHY
they're structured this way.

---

## 1. System Overview

This is a Claude Code configuration system that enforces development practices through:
- **Deterministic hooks** (mechanical enforcement at every lifecycle event)
- **Specialized agents** (Planner, Implementer, Guardian divide responsibilities)
- **Git worktrees** (isolated feature branches, main stays sacred)
- **GitHub Issues** (durable task tracking via /backlog)

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        User describes feature                        │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
                 ┌──────────────────────────────┐
                 │   CLAUDE.md (instructions)   │
                 │   - Cornerstone Belief       │
                 │   - Sacred Practices         │
                 │   - Dispatch Rules           │
                 └──────────────┬───────────────┘
                                ▼
        ┌──────────────────────────────────────────────┐
        │         Orchestrator (main context)          │
        │   Reads → Analyzes → Dispatches to agents   │
        └───┬────────────┬────────────┬────────────────┘
            │            │            │
            ▼            ▼            ▼
    ┌───────────┐  ┌────────────┐  ┌──────────┐
    │  Planner  │  │Implementer │  │ Guardian │
    │           │  │            │  │          │
    │ Phase 1-2 │  │  Phase 3-4 │  │ Phase 5  │
    │ Research  │  │   Tests +  │  │ Commit + │
    │ + Plan    │  │    Code    │  │  Merge   │
    └─────┬─────┘  └─────┬──────┘  └────┬─────┘
          │              │               │
          ▼              ▼               ▼
    MASTER_PLAN.md  .worktrees/    git commit
    GitHub Issues   feature-name   git merge → main

┌─────────────────────────────────────────────────────────────────────┐
│                     Hook System (enforcement layer)                  │
├──────────────┬──────────────┬──────────────┬─────────────────────────┤
│ PreToolUse   │ PostToolUse  │SessionStart  │ SubagentStart/Stop      │
│              │              │              │                         │
│ guard.sh     │ track.sh     │session-init  │ subagent-start.sh       │
│ doc-gate.sh  │ lint.sh      │              │ check-implementer.sh    │
│ test-gate.sh │ test-runner  │              │                         │
│ mock-gate.sh │              │              │                         │
│ branch-guard │              │              │                         │
│ plan-check   │              │              │                         │
│ auto-review  │              │              │                         │
└──────┬───────┴──────┬───────┴──────┬───────┴─────────┬───────────────┘
       │              │              │                 │
       ▼              ▼              ▼                 ▼
    DENY/ALLOW   additionalContext  statusline     .agent-findings
    updatedInput                    injection       .proof-status

┌─────────────────────────────────────────────────────────────────────┐
│                         State Files (persistence)                    │
├──────────────────┬─────────────────┬────────────────┬───────────────┤
│ .test-status     │ .proof-status   │ .agent-findings│ .plan-status  │
│ pass|fail|pending│ verified|pending│ issues list    │ churn %       │
│                  │                 │                │               │
│ .session-changes │ .statusline-    │ .subagent-     │ .plan-drift   │
│ (file list)      │ cache (JSON)    │ tracker        │               │
└──────────────────┴─────────────────┴────────────────┴───────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      Configuration (settings.json)                   │
├─────────────────────────────────────────────────────────────────────┤
│  PreToolUse:   Bash → guard.sh, auto-review.sh                      │
│                Write|Edit → doc-gate.sh, branch-guard.sh            │
│                Task → task-track.sh                                  │
│  PostToolUse:  Write|Edit → track.sh, test-runner.sh, lint.sh       │
│  SessionStart: startup → session-init.sh                            │
│  SubagentStop: implementer → check-implementer.sh                   │
│                                                                      │
│  settings.local.json can override any hook (user-specific)          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Flow: Feature Request End-to-End

### Typical Feature Implementation Flow

```
User: "Add email validation to the signup form"
   │
   ▼
[SessionStart hook: session-init.sh fires]
   │ Reads: MASTER_PLAN.md, git status, .test-status
   │ Injects: "Plan: Phase 2/5, 3 dirty files, 2 worktrees, tests: pass"
   │
   ▼
Orchestrator analyzes request
   │ Checks: MASTER_PLAN.md exists? Is this planned?
   │ Decision: Not in plan → dispatch to Planner
   │
   ▼
PLANNER AGENT (agents/planner.md)
   │
   ├─ Phase 1: Problem decomposition
   │   - User requirements (P0/P1/P2)
   │   - Success metrics
   │   - Evidence gathering
   │
   ├─ Phase 2: Architecture + Research gate
   │   - Check .claude/research-log.md
   │   - If gaps exist → /deep-research
   │   - Select libraries, patterns
   │
   ├─ Output: MASTER_PLAN.md
   │   - Phases with DEC-IDs
   │   - Requirements (REQ-P0-001, etc.)
   │   - Decision annotations
   │
   └─ Create GitHub Issues (one per phase)
       │
       ▼
Orchestrator dispatches to Guardian to set up workspace
       │
       ▼
GUARDIAN AGENT (agents/guardian.md)
   │
   ├─ git worktree add .worktrees/signup-validation -b feature/signup-validation
   │
   └─ Returns: "Worktree created at .worktrees/signup-validation"
       │
       ▼
Orchestrator dispatches to Implementer
       │
       ▼
IMPLEMENTER AGENT (agents/implementer.md)
   │
   ├─ Phase 3: Test-first implementation
   │   │
   │   ├─ Write failing tests
   │   │   [PostToolUse: track.sh logs to .session-changes]
   │   │   [PostToolUse: test-runner.sh runs tests in background]
   │   │   [Updates .test-status: fail|2|<epoch>]
   │   │
   │   ├─ Implement feature
   │   │   [PreToolUse: doc-gate.sh checks for header + @decision]
   │   │   [PreToolUse: branch-guard.sh blocks writes to main]
   │   │   [PostToolUse: lint.sh runs, exit code 2 triggers retry if fails]
   │   │
   │   └─ Tests pass
   │       [test-runner.sh updates .test-status: pass|0|<epoch>]
   │
   ├─ Phase 4: Decision annotation
   │   └─ Add @decision DEC-SIGNUP-001 to validation.ts
   │       [doc-gate.sh verifies presence]
   │
   ├─ Phase 4.5: Verification checkpoint
   │   │
   │   ├─ Discover MCP tools (Playwright, browser, etc.)
   │   ├─ Collect proof:
   │   │   - Test output (pytest/vitest results)
   │   │   - Live demo (dev server + URL)
   │   │   - MCP evidence (screenshot, API response)
   │   │
   │   ├─ Present to user:
   │   │   "Tests passing (8/8). Dev server at localhost:3000/signup.
   │   │    Screenshot shows validation working. Verify? Reply 'verified'"
   │   │
   │   └─ User confirms → write .proof-status: verified|<epoch>
   │
   └─ Exit implementer agent
       │
       ▼
[SubagentStop:implementer hook: check-implementer.sh fires]
   │ Reads: .session-changes, scans for @decision coverage
   │ Checks: .proof-status = verified?
   │ If issues found → inject findings, agent resumes
   │ If OK → returns findings to orchestrator
   │
   ▼
Orchestrator dispatches to Guardian for commit
   │
   ▼
GUARDIAN AGENT (agents/guardian.md)
   │
   ├─ [PreToolUse: guard.sh Check 7 — test-status gate]
   │   Reads .test-status: pass|0|<epoch> → allow
   │
   ├─ [PreToolUse: guard.sh Check 8 — proof-of-work gate]
   │   Reads .proof-status: verified|<epoch> → allow
   │
   ├─ git add src/validation.ts tests/validation.test.ts
   │
   ├─ git commit -m "feat: add email validation to signup form
   │                    Co-Authored-By: Claude Opus 4.6"
   │   [guard.sh Check 2: not on main → allow]
   │   [guard.sh Check 7: tests passing → allow]
   │
   ├─ git checkout main
   ├─ git merge feature/signup-validation
   │   [guard.sh Check 6: test-status gate → allow]
   │
   ├─ Update MASTER_PLAN.md (if phase boundary)
   │   - Mark Phase 2: completed
   │   - Add to Decision Log
   │
   ├─ Close GitHub Issue #42
   │
   └─ git push origin main
       │
       ▼
Done. Feature merged to main.
```

### Hooks That Fired

| Event | Hook | Purpose |
|-------|------|---------|
| SessionStart | session-init.sh | Inject plan/git/test context |
| PreToolUse:Write | doc-gate.sh | Enforce documentation headers |
| PreToolUse:Write | branch-guard.sh | Block writes on main |
| PostToolUse:Write | track.sh | Log file changes to .session-changes |
| PostToolUse:Write | test-runner.sh | Run tests async, update .test-status |
| PostToolUse:Write | lint.sh | Run linter, exit 2 if fails |
| PreToolUse:Bash (commit) | guard.sh Check 7 | Require tests passing |
| PreToolUse:Bash (commit) | guard.sh Check 8 | Require proof-of-work verified |
| PreToolUse:Bash (merge) | guard.sh Check 6 | Require tests passing |
| SubagentStop:implementer | check-implementer.sh | Validate worktree + @decision + proof |

---

## 3. Hook Execution Model

### Protocol

All hooks communicate via **JSON stdin/stdout**. Exit code 0 = success. Non-zero = hook error (logged, doesn't block).

#### Input Format (stdin)

```json
{
  "tool_name": "Bash|Write|Edit|Read|Grep|...",
  "tool_input": {
    "command": "git commit -m 'fix'",
    "file_path": "/path/to/file.ts",
    "content": "..."
  },
  "cwd": "/current/working/directory"
}
```

SubagentStart/Stop receive:
```json
{
  "subagent_type": "planner|implementer|guardian",
  "response": "..."
}
```

#### Output Formats (stdout)

**PreToolUse: Deny**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Cannot commit on main. Create a worktree."
  }
}
```

**PreToolUse: Rewrite (transparent)**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Rewrote /tmp/ to project tmp/",
    "updatedInput": {
      "command": "mkdir -p /project/tmp && echo data > /project/tmp/file"
    }
  }
}
```

**PreToolUse: Advisory**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "Warning: plan is stale (20% source churn)"
  }
}
```

**PostToolUse: Feedback**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Linter found 3 issues. Fix and retry."
  }
}
```

Exit code 2 in PostToolUse triggers a feedback loop (model retries with the additionalContext).

**Stop Hooks: System Message**
```json
{
  "systemMessage": "Session summary: 12 files changed, 3 @decisions added, tests pass"
}
```

**Stop Hooks: Block**
```json
{
  "decision": "block",
  "reason": "Implementer output missing proof-of-work verification"
}
```

### Lifecycle Events

| Event | When | Example Hooks |
|-------|------|---------------|
| **SessionStart** | Fresh session, /clear, /compact | session-init.sh |
| **PreToolUse** | Before every tool call | guard.sh, doc-gate.sh, auto-review.sh |
| **PostToolUse** | After every tool call | track.sh, lint.sh, test-runner.sh |
| **SubagentStart** | Agent begins execution | subagent-start.sh |
| **SubagentStop** | Agent completes | check-implementer.sh |

### State File Communication

Hooks don't share memory. They communicate via **state files** in `.claude/`:

| File | Writer | Readers | Purpose |
|------|--------|---------|---------|
| `.test-status` | test-runner.sh | guard.sh, session-init.sh | Gate commits on passing tests |
| `.proof-status` | Implementer (user verified) | guard.sh, check-implementer.sh | Gate commits on live verification |
| `.session-changes` | track.sh | check-implementer.sh, surface.sh | Track modified files per session |
| `.agent-findings` | check-implementer.sh | Orchestrator | Surface validation issues |
| `.statusline-cache` | context-lib.sh | statusline.sh | Enrich status bar |
| `.subagent-tracker` | task-track.sh | statusline.sh | Track active agents |
| `.plan-drift` | surface.sh | prompt-submit.sh | Detect code/plan divergence |

**Format examples:**

`.test-status`: `pass|0|1644512345` (status|fail_count|epoch)
`.proof-status`: `verified|1644512345` (status|epoch)
`.agent-findings`: Line-delimited issues
`.statusline-cache`: JSON `{dirty:3,worktrees:2,plan:"Phase 2/5",test:"pass"}`

### Rewrite vs Deny

**Prefer rewrite** when intent is correct but method is unsafe:
- `/tmp/file` → `project/tmp/file` (Check 1)
- `--force` → `--force-with-lease` (Check 3)
- `git worktree remove` → `cd main && git worktree remove` (Check 5)

**Use deny** when action is fundamentally wrong:
- Commits on main (Check 2)
- Force push to main/master (Check 3)
- Tests failing (Check 7)
- Proof-of-work missing (Check 8)

---

## 4. Key Design Decisions

### DEC-GUARD-001: Multi-tier command safety gate
**File:** hooks/guard.sh
**Rationale:** Enforces Sacred Practices mechanically via deny (hard blocks) and updatedInput (transparent rewrites). Nuclear deny blocks catastrophic commands unconditionally. Test gates (Checks 7-8) ensure quality before commits.

### DEC-AUTOREVIEW-001: Three-tier command classification
**File:** hooks/auto-review.sh
**Rationale:** Static prefix matching in settings.json cannot distinguish `git log` (safe) from `git reset --hard` (risky). Recursive command decomposition with segment-level analysis classifies commands into safe/risky/unknown tiers. Only risky commands require user approval.

### DEC-MOCK-001: Escalating mock detection gate
**File:** hooks/mock-gate.sh
**Rationale:** Sacred Practice #5 mandates "Real unit tests, not mocks." Detects 15+ mock patterns (jest.fn, unittest.mock, mockito, etc.) and denies writes. Backed by arXiv 2602.00409 research showing mocks correlate with test brittleness.

### DEC-TEST-001: Fixture-based contract testing for hooks
**File:** tests/run-hooks.sh
**Rationale:** Hooks are deterministic shell scripts that parse JSON stdin and emit JSON stdout. Contract tests use fixture files (input.json → expected-output.json) to verify hook behavior without running actual git/npm/docker commands.

### DEC-CACHE-001: Statusline cache for status bar enrichment
**File:** hooks/context-lib.sh
**Rationale:** Hooks already compute git/plan/test state on every prompt. Cache this data so statusline.sh can render a rich status bar without re-parsing. Atomic writes prevent race conditions.

### DEC-CACHE-002: Status bar enrichment with cached hook data
**File:** scripts/statusline.sh
**Rationale:** Reads `.statusline-cache` JSON to display git dirty count, worktree count, plan phase, test status, and active agents in the status bar. Updates every prompt via prompt-submit.sh.

### DEC-CACHE-003: PreToolUse:Task as SubagentStart replacement
**File:** hooks/task-track.sh
**Rationale:** SubagentStart hooks don't fire in Claude Code v2.1.38. Use PreToolUse:Task matcher to detect agent invocations via `tool_input.task` field, updating `.subagent-tracker` for status bar display.

### DEC-SUBAGENT-001: Subagent lifecycle tracking via state file
**File:** hooks/context-lib.sh
**Rationale:** SubagentStart/Stop hooks fire per-event but don't aggregate. Line-based state file tracks ACTIVE/DONE records with timestamps for status bar agent activity display.

### DEC-COMPACT-001: Smart compaction suggestions
**File:** hooks/prompt-submit.sh
**Rationale:** Proactively suggest `/compact` at predictable checkpoints (35, 60 prompts or 45-60 minute sessions) to prevent context window pressure degrading instruction adherence.

### DEC-UPDATE-001: Git-based auto-update with breaking change detection
**File:** scripts/update-check.sh
**Rationale:** Auto-apply safe updates to keep harness current across devices. Scans commit subjects for `BREAKING:` prefix. Safe updates (feat, fix, refactor) auto-merge. Breaking changes notify user with upgrade instructions.

### DEC-UPLEVEL-CI: Rewrite test suite from scratch
**Status:** pending (Phase 1)
**Rationale:** Start fresh with clean test architecture. Modular test files replace monolithic run-hooks.sh. Gate hook behavioral tests, context-lib.sh unit tests, integration tests, session lifecycle e2e tests.

### DEC-UPLEVEL-QUICKWINS: Tackle all 9 quick wins in one worktree
**Status:** pending (Phase 2)
**Rationale:** One branch, one PR, one review cycle for efficiency. Fixes shellcheck warnings, renames .todo-count → .statusline-cache, adds command descriptions, etc.

### DEC-UPLEVEL-TESTING: Full pyramid (unit + integration + e2e)
**Status:** pending (Phase 3)
**Rationale:** All gate hooks + context-lib + integration tests. Full test coverage for core enforcement mechanisms and shared libraries.

### DEC-UPLEVEL-QUALITY: Broader consolidation sweep
**Status:** pending (Phase 4)
**Rationale:** Extract shared constants and deduplicate patterns. Reduce drift risk by consolidating SOURCE_EXTENSIONS, LABEL definitions, and staleness thresholds.

### DEC-UPLEVEL-DOCS: Function docs + ARCHITECTURE.md
**Status:** in-progress (Phase 5)
**Rationale:** Raise function doc coverage to 80%+. Standalone architecture document explains system structure, data flow, and design decisions for Future Implementers.

### DEC-UPLEVEL-TODOSH: Split god file + write tests
**Status:** deferred (Phase 6)
**Rationale:** scripts/todo.sh is 1500+ lines. Extract cmd_* functions into separate files. Add contract tests for each command.

---

## 5. Extension Points

### Adding a New Hook

1. **Create hook script** in `hooks/` (e.g., `hooks/my-gate.sh`)
2. **Add shebang + header** with @decision annotation
3. **Source log.sh** for JSON parsing: `source "$(dirname "$0")/log.sh"`
4. **Read input**: `HOOK_INPUT=$(read_input)`
5. **Emit JSON response** (deny/allow/additionalContext)
6. **Register in settings.json**:
   ```json
   {
     "hook": "PreToolUse",
     "matcher": "Write",
     "command": ["bash", "~/.claude/hooks/my-gate.sh"]
   }
   ```
7. **Write contract tests** in `tests/fixtures/my-gate/`

### Adding a New Agent

1. **Create agent markdown** in `agents/my-agent.md`
2. **Define role + workflow** (phases, inputs, outputs)
3. **Add SubagentStart context** in `hooks/subagent-start.sh`
4. **Add SubagentStop validation** in `hooks/check-my-agent.sh`
5. **Update dispatch rules** in `CLAUDE.md`

### Adding State Files

1. **Choose format**: pipe-delimited, JSON, or line-based
2. **Atomic writes**: `mv tmp.$$ target` to prevent race conditions
3. **Document in context-lib.sh** with writer/reader annotations
4. **Add to .gitignore**: `.claude/.my-state`

---

## 6. Anti-Patterns

### Don't: Rely on instructions alone
**Problem:** Context window pressure degrades instruction adherence.
**Solution:** Enforce via hooks. Instructions guide, hooks enforce.

### Don't: Use /tmp/ for artifacts
**Problem:** Littering the user's machine, hard to debug, survives crashes.
**Solution:** `project/tmp/` directory. guard.sh Check 1 rewrites automatically.

### Don't: Mock internal modules
**Problem:** Tests become brittle, test the mock not the code.
**Solution:** Test real implementations. Mocks only for external boundaries (APIs, DBs).

### Don't: Work on main
**Problem:** Can't rollback, can't experiment, pollutes history.
**Solution:** git worktrees. branch-guard.sh blocks source writes on main.

### Don't: Commit without tests
**Problem:** Regressions, broken builds, wasted debugging time.
**Solution:** test-gate.sh blocks commits when `.test-status != pass`.

### Don't: Track tasks in files
**Problem:** No timestamps, no web visibility, no mobile access, easy to lose.
**Solution:** GitHub Issues via `/backlog`. Durable, searchable, timestamped.

---

## 7. Glossary

**Sacred Practices:** Ten core principles (Always Use Git, Main is Sacred, Nothing Done Until Tested, etc.) enforced mechanically by hooks.

**Worktree:** Isolated git working directory. Feature work happens in `.worktrees/feature-name`. Main stays clean and deployable.

**@decision:** Annotation format for documenting significant implementation choices. Required for 50+ line files. Format: `@decision DEC-COMPONENT-NNN`, `@title`, `@status`, `@rationale`.

**Proof-of-work:** Phase 4.5 verification checkpoint. Implementer must demonstrate the feature working (tests + live demo + MCP evidence) and get user confirmation before commit.

**Test status gate:** guard.sh Checks 7-8. Commits and merges blocked when `.test-status != pass` or `.proof-status != verified`.

**Transparent rewrite:** guard.sh updates the command without model awareness. Used for safe fixes (/tmp/ → project/tmp/, --force → --force-with-lease).

**State file:** Persistence mechanism for hook-to-hook communication. Stored in `.claude/`. Atomic writes prevent race conditions.

**Phase boundary:** Completion of a major MASTER_PLAN.md phase. Triggers plan status update and Decision Log population.

**Claude scratchpad:** `/private/tmp/claude-*` directories. Exempt from /tmp/ rewrite rule (Check 1) because Claude Code uses them internally.

**Meta-repo:** The `~/.claude` configuration repository itself. Exempt from test gates and proof-of-work requirements because it's infrastructure, not user projects.

---

**Last updated:** 2026-02-11
**Maintainers:** See CLAUDE.md Cornerstone Belief — Future Implementers rely on this doc
