# Worktree Management (Agent Guidance)

Internal guidance for agents on git worktree lifecycle management.
Enforces Sacred Practice #2: Main is Sacred.

## Purpose

Worktrees enable parallel, isolated development without polluting main. This skill
defines WHEN agents should create worktrees and HOW they should manage them.

This is NOT a user-invocable skill. It's guidance for:
- **Guardian**: Creates/removes worktrees, manages branch lifecycle
- **Implementer**: Works within worktrees, never on main
- **Orchestrator**: Invokes Guardian for worktree operations

---

## Decision Flow: When to Create a Worktree

```
Starting implementation work?
    │
    ├─► Check current branch
    │       │
    │       ├─► On main/master? ──► MUST create worktree first
    │       │                           │
    │       │                           └─► Invoke Guardian
    │       │
    │       └─► On feature branch? ──► Verify it's a worktree
    │                                       │
    │                                       ├─► Yes ──► Proceed
    │                                       │
    │                                       └─► No (checkout) ──► Consider worktree
    │
    └─► If branch-guard.sh blocks ──► Guardian creates worktree
```

### Triggers for Worktree Creation

1. **New phase from MASTER_PLAN.md** — Each phase gets its own worktree
2. **branch-guard.sh denial** — Hook blocked write on main
3. **Parallel work needed** — Multiple features in progress
4. **Hotfix while mid-feature** — Preserve current work, branch for fix

---

## Agent Responsibilities

### Guardian Agent

**Creates worktrees when:**
- Starting a new implementation phase
- User requests feature isolation
- Implementer needs a clean workspace
- Hotfix required while other work in progress

**Worktree creation protocol:**
```bash
# 1. Verify on main and clean
git status --porcelain  # Should be empty or user-approved

# 2. Create worktree with feature branch
git worktree add ../<feature-name> -b feature/<feature-name>

# 3. Confirm to orchestrator
# Report: path, branch name, base commit
```

**Removes worktrees when:**
- Phase complete and merged
- User explicitly requests cleanup
- Worktree abandoned (stale, no commits in 30+ days)

**Removal protocol:**
```bash
# 1. Check for uncommitted changes
git -C ../<worktree> status --porcelain

# 2. Check for unpushed commits
git -C ../<worktree> log @{u}.. --oneline 2>/dev/null

# 3. If dirty or unpushed, WARN and require explicit approval

# 4. Remove worktree
git worktree remove ../<worktree>

# 5. Optionally delete branch (ask user)
git branch -d feature/<feature-name>
```

### Implementer Agent

**Must verify before any implementation:**
1. NOT on main/master branch
2. Working in a proper worktree (not just a checkout)
3. Worktree is for the correct feature/phase

**If on main:**
- DO NOT proceed with implementation
- Request Guardian to create appropriate worktree
- Wait for confirmation before continuing

**Within worktree:**
- Free to create commits
- Run tests
- Make changes
- Still requires Guardian for merge back to main

### Orchestrator

**Worktree awareness:**
- Check active worktrees at session start (session-init.sh provides this)
- Know which worktree corresponds to which MASTER_PLAN.md phase
- Route implementation requests to correct worktree context

**When user requests implementation:**
1. Check if appropriate worktree exists
2. If not, invoke Guardian to create one
3. Then invoke Implementer in that worktree context

---

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feature/<name>` | `feature/auth-oauth` |
| Bugfix | `fix/<issue>` | `fix/null-pointer-123` |
| Phase | `phase/<n>-<name>` | `phase/2-api-integration` |
| Hotfix | `hotfix/<desc>` | `hotfix/security-patch` |

Worktree directory: `../<branch-name-without-prefix>`
- `feature/auth-oauth` → `../auth-oauth`
- `phase/2-api-integration` → `../phase-2-api-integration`

---

## Integration with Hooks

### branch-guard.sh
Blocks source writes on main. When triggered:
- Message directs to invoke Guardian for worktree creation
- Agent should NOT attempt to bypass

### check-implementer.sh
Validates implementer worked in worktree:
- Flags if current branch is main/master
- Reports as validation issue

### session-init.sh
Injects active worktrees into session context:
- Orchestrator sees all worktrees at session start
- Enables routing to correct context

---

## Common Scenarios

### Scenario 1: Fresh Implementation Start
```
User: "Implement the auth feature from MASTER_PLAN.md"

Orchestrator:
  1. Check: On main, no worktree for auth
  2. Invoke Guardian: "Create worktree for auth feature"

Guardian:
  1. git worktree add ../auth-feature -b feature/auth
  2. Confirm: "Created ../auth-feature on feature/auth"

Orchestrator:
  3. Invoke Implementer in ../auth-feature context
```

### Scenario 2: Hotfix While Mid-Feature
```
User: "There's a prod bug, need to fix immediately"

Orchestrator:
  1. Current: In ../auth-feature worktree
  2. Invoke Guardian: "Create hotfix worktree, preserve current work"

Guardian:
  1. Stash any uncommitted in auth-feature (or warn)
  2. git worktree add ../hotfix-prod -b hotfix/prod-issue
  3. Confirm: "Created ../hotfix-prod, auth-feature preserved"

Orchestrator:
  3. Invoke Implementer in ../hotfix-prod
  4. After fix merged, return to auth-feature context
```

### Scenario 3: Phase Completion
```
Implementer: "Phase 1 complete, tests passing"

Orchestrator:
  1. Invoke Guardian for merge review

Guardian:
  1. Review changes in phase-1 worktree
  2. Merge to main (with approval)
  3. Ask: "Remove phase-1 worktree?"
  4. If yes: git worktree remove ../phase-1
```

---

## Safety Rules

1. **Never force-remove dirty worktrees** — Always warn, require explicit approval
2. **Never delete branches with unpushed commits** — Warn and confirm
3. **Main worktree is immutable** — Cannot be removed
4. **One worktree per branch** — Git enforces this, but agents should know
5. **Worktrees share object database** — Disk-efficient, but don't delete .git

---

## Verification Commands

Agents can use these to verify worktree state:

```bash
# List all worktrees
git worktree list

# Check if in a worktree (vs main repo)
git rev-parse --git-common-dir  # Differs from --git-dir in worktrees

# Get worktree root
git rev-parse --show-toplevel

# Check worktree status
git -C <path> status --porcelain
```
