---
name: plan-sync
description: Reconcile MASTER_PLAN.md with codebase @decision annotations and phase status
---

# Plan Sync Skill

Reconcile MASTER_PLAN.md with the actual state of the codebase. Scans @decision annotations in code, compares against the plan's phases and decision IDs, and generates a reconciliation report with optional auto-update.

Invoked as `/plan-sync`.

## Prerequisites

- A `MASTER_PLAN.md` file must exist in the project root
- The project should have source files with @decision annotations (see decision-parser skill)

## Procedure

### Step 1: Locate MASTER_PLAN.md

Search for `MASTER_PLAN.md` in the current project root. If not found, report error and stop.

### Step 2: Parse Plan Structure

Extract from MASTER_PLAN.md:
- **Phases**: Header, status (planned/in-progress/completed), description
- **Decision IDs**: All `DEC-COMPONENT-NNN` and `ADR-NNN` references
- **Decision Log sections**: Entries in completed phase logs
- **Original Intent**: Verify the intent section is preserved

Build a plan manifest:

```
Phase 1: [title] — Status: [planned|in-progress|completed]
  Expected decisions: DEC-AUTH-001, DEC-AUTH-002
  Decision log entries: [count]

Phase 2: [title] — Status: [planned|in-progress|completed]
  Expected decisions: DEC-API-001
  Decision log entries: [count]
```

### Step 3: Scan Codebase for @decision Annotations

Search source directories (`src/`, `lib/`, `app/`, `pkg/`, `cmd/`, `internal/`, or project root) for all @decision annotations using patterns:

- `@decision <ID>` (JSDoc block format)
- `# DECISION: ...` (Python/Shell inline)
- `// DECISION(<ID>): ...` (Go/Rust inline)

Extract from each annotation:
- Decision ID
- Title
- Status (proposed/accepted/deprecated/superseded)
- File path and line number
- Rationale (presence check)

Build a code manifest:

```
DEC-AUTH-001 — "Token refresh strategy" — accepted — src/auth/token.ts:42
DEC-AUTH-002 — "Session storage" — accepted — src/auth/session.ts:15
DEC-API-001 — "Rate limiting approach" — proposed — src/api/middleware.ts:88
```

### Step 4: Generate Reconciliation Report

Compare the plan manifest against the code manifest. Report format:

```markdown
# Plan Reconciliation Report

## Phase Status
| Phase | Title | Plan Status | Decisions Expected | Decisions Found | Gap |
|-------|-------|-------------|-------------------|-----------------|-----|
| 1 | Authentication | completed | 2 | 2 | 0 |
| 2 | API Layer | in-progress | 3 | 1 | 2 |
| 3 | Frontend | planned | 0 | 0 | 0 |

## Decision Sync

### In Plan AND In Code (Synced)
- DEC-AUTH-001: "Token refresh strategy" — Plan: Phase 1 — Code: src/auth/token.ts:42

### In Code, NOT In Plan (Unplanned)
- DEC-CACHE-001: "Redis caching strategy" — Code: src/cache/redis.ts:30
  → Action: Add to MASTER_PLAN.md under appropriate phase

### In Plan, NOT In Code (Unimplemented)
- DEC-API-002: "Pagination strategy" — Plan: Phase 2
  → Action: Implement or mark phase as in-progress

## Status Mismatches
- Phase 2 marked "completed" but DEC-API-002 has no code implementation
  → Suggested: Revert phase status to "in-progress"

## Decision Log Gaps
- Phase 1 (completed): Decision Log has 2 entries ✓
- Phase 2 (completed): Decision Log is EMPTY — Guardian must populate
```

### Step 5: Suggest Updates (Interactive)

After generating the report, ask the user:

> "Would you like me to update MASTER_PLAN.md with the reconciliation findings?"

If approved, make these updates:
1. Add unplanned code decisions to the appropriate phase (or create an "Unplanned Decisions" section)
2. Update phase statuses based on implementation evidence
3. Flag unimplemented plan items with `<!-- UNIMPLEMENTED -->` comments
4. Populate empty Decision Log sections for completed phases

**Never auto-update without explicit user approval.**

## Output Location

- Report is displayed inline in the conversation
- If the user requests a file, save to `{project_root}/.claude/plan-reconciliation-report.md`
- The report is ephemeral by default (Code is Truth — the plan and code are the sources, not the report)

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No MASTER_PLAN.md | Error: "No MASTER_PLAN.md found. Run the planner agent first." |
| No @decision annotations in code | Report shows all plan decisions as unimplemented |
| No phases in plan | Skip phase-level analysis, only do decision ID comparison |
| Decision ID in code doesn't match DEC-COMPONENT-NNN format | Flag as validation warning |
| Multiple files contain same decision ID | Flag as duplicate — decisions must be unique |

## Relationship to Other Components

- **surface.sh** (Stop hook): Runs a lightweight version of this reconciliation automatically at session end. This skill provides the full interactive version.
- **plan-validate.sh** (PostToolUse hook): Validates MASTER_PLAN.md structure on write. This skill validates plan-to-code alignment.
- **decision-parser** (skill): Provides the annotation format definitions this skill scans for.
- **Guardian agent**: Responsible for acting on reconciliation findings (updating plan, merging, committing).
