---
name: plan-quick
description: Lightweight planning for small, well-understood tasks. Produces a concise plan without MASTER_PLAN.md ceremony.
context: fork
agent: general-purpose
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash(read-only)
  - AskUserQuestion
argument-hint: "[task description] [--perspective security|performance|simplicity|maintainability|cost|reliability]"
---

# Quick Plan

A fast-path planning mode for small, well-understood tasks. Produces a concise, actionable plan without REQ-IDs, research gates, MASTER_PLAN.md, or issue creation.

**This mode does NOT create:** MASTER_PLAN.md, GitHub issues, REQ-IDs, DEC-IDs, or research log entries.

**When to upgrade:** If the task involves 3+ files, architectural decisions, unfamiliar domains, or cross-cutting concerns, use the full planner (`/plan`) instead.

## Perspective

If `--perspective <lens>` is provided, weight the analysis toward that lens. Available: security, performance, simplicity, maintainability, cost, reliability. Default: balanced.

## Process

### Step 1: Understand Requirements
- Restate the task in your own words to confirm understanding
- Identify the core problem and desired outcome
- List constraints and assumptions
- If anything is unclear, ask before proceeding

### Step 2: Explore Codebase
- Find existing patterns relevant to the task
- Trace code paths that will be affected
- Identify conventions to follow (naming, structure, error handling)
- Note any existing tests that cover related functionality

### Step 3: Design Solution
- Describe the approach in 3-5 sentences
- Consider trade-offs — why this approach over alternatives
- Follow existing codebase patterns and conventions
- Call out risks or edge cases
- If a perspective was specified, weight trade-offs accordingly

### Step 4: Detail the Plan
- Step-by-step implementation sequence
- Dependencies and ordering constraints
- What to test and how
- Estimated scope (small / medium / large)

### Step 5: Critical Files for Implementation
Conclude with 3-5 files that are central to the implementation:
```
## Critical Files
- path/to/file1.ext - [why this file matters]
- path/to/file2.ext - [why this file matters]
- path/to/file3.ext - [why this file matters]
```

## Output Format

Present the plan as a single, readable document. No ceremony — just clear thinking. The output is conversational, not a formal artifact.

## Constraints

- This skill is READ-ONLY. Do not write, edit, or create any files.
- Do not create MASTER_PLAN.md, issues, or any persistent artifacts.
- If the task is too complex for a quick plan, say so and recommend `/plan` instead.
