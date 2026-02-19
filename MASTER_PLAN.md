# MASTER_PLAN: Claude System v3 — Hardening and Reliability

## Project Overview
**Type:** meta-infrastructure (hooks, agents, skills, commands)
**Languages:** bash (78%), markdown (15%), python (7%)
**Root:** /Users/turla/.claude

### Architecture
  hooks/     — 28 lifecycle hooks (session, tool-use, subagent, stop)
  agents/    — 4 agent prompts (planner, implementer, tester, guardian)
  skills/    — 8 skills (deep-research, decide, consume-content, ...)
  commands/  — 6 slash commands (backlog, compact, ...)
  scripts/   — Utility scripts (todo, update-check, batch-fetch)
  traces/    — Agent trace protocol (43 manifests, 39 indexed, 489 in oldTraces/)
  tests/     — Hook validation suite (141 tests)
  observatory/ — Self-improvement flywheel (analyze, suggest, report)

### Active Work
  v3 Hardening — auto-verify pipeline repair, proof-of-work chain completion, shared library consolidation
  2 stale worktrees to clean: feature/guard-fix, feature/v2-session-hooks (both merged, clean)

---

## Original Intent

> v2 built the governance + observability infrastructure. It works — 140/141 tests pass,
> all 6 phases completed. But production reveals reliability gaps: auto-verify never fires
> (dead fast path), the proof-of-work chain has untested links, guard.sh carries dead
> rewrite() code, and the shared library has accumulated duplication across 14 hooks.
> v3 hardens the existing system. No new features — just making what exists bulletproof.

## Problem Statement

The system's enforcement layer is functionally complete but has reliability blind spots
discovered through production use (2026-02-18 through 2026-02-19):

1. **Auto-verify is dead.** The fast path that skips manual user approval when tester
   confidence is High has never fired in production. `check-tester.sh` cannot find
   the `AUTOVERIFY: CLEAN` signal in the SubagentStop payload (#129). Every tester run
   falls back to manual approval, adding unnecessary friction to every merge cycle.

2. **Proof-of-work chain is partially untested.** Issues #41-44 (v1 proof chain hardening)
   are open. Codebase audit shows: guard.sh Check 8, track.sh invalidation, and
   session-init.sh proof clearing all work correctly. But: session-summary.sh lacks proof
   status reporting, subagent-start.sh lacks proof status injection for implementer,
   no contract tests exist (test-proof-chain.sh), and HOOKS.md is missing proof clearing
   documentation for session-init.sh.

3. **Guard.sh dead code.** #92 identified all rewrite() calls as silently broken (updatedInput
   not supported in PreToolUse hooks). #98 converted most to deny(). Final sweep needed
   to confirm all rewrites are converted and close the issue.

4. **Shared library duplication.** 4 implementations of session file lookup logic across
   hooks (#7). compact-preserve.sh reimplements context-lib.sh functions. 9/16 hooks
   use raw jq instead of get_field(). One failing test (crash detection) caused by
   missing source-lib.sh in test subshell.

**Dominant Constraint:** reliability (every enforcement gap is a bypass risk)

## Goals & Non-Goals

### Goals
- REQ-GOAL-001: Auto-verify fast path fires in production when tester signals High confidence
- REQ-GOAL-002: Proof-of-work chain is fully tested with contract tests covering all enforcement points
- REQ-GOAL-003: All hook shared code flows through context-lib.sh (single source of truth)
- REQ-GOAL-004: Test suite reaches 0 failures on main (currently 1 failure)

### Non-Goals
- REQ-NOGO-001: Multi-instance plan file scoping (#115) — deferred to separate plan, touches 14+ hooks
- REQ-NOGO-002: Hook status visualization (#94) — enhancement, not hardening
- REQ-NOGO-003: New features or capabilities — this plan fixes what exists
- REQ-NOGO-004: todo.sh refactoring (#57/#58/#69) — separate initiative
- REQ-NOGO-005: Release process or branch protection (#67/#61) — separate initiative

## Requirements

### Must-Have (P0)

- REQ-P0-001: Auto-verify signal extraction works in check-tester.sh.
  Acceptance: Given tester response contains "AUTOVERIFY: CLEAN", When check-tester.sh
  runs, Then .proof-status is set to "verified" and AUTO-VERIFIED is emitted.

- REQ-P0-002: Diagnostic logging in check-tester.sh reveals payload structure.
  Acceptance: check-tester.sh logs RESPONSE_TEXT length and AUTOVERIFY grep result to stderr.

- REQ-P0-003: Guardian session context data flow validated end-to-end (#121).
  Acceptance: Test proves event log -> get_session_summary_context() -> subagent-start.sh
  injection -> Guardian startup context with correct trajectory stats.

- REQ-P0-004: v2 lifecycle integration test covers full 10-stage arc (#122).
  Acceptance: INTENT-06 in test-v2-e2e.sh exercises session_start through cross-session
  context with 10 sequential assertions completing in under 10 seconds.

- REQ-P0-005: session-summary.sh includes proof status in stop output (#42 residual).
  Acceptance: When .proof-status exists, session summary GIT_LINE includes "Proof: verified."
  or "Proof: PENDING." or "Proof: not started."

- REQ-P0-006: subagent-start.sh injects current proof status for implementer (#42 residual).
  Acceptance: When implementer spawns, context includes proof status (verified/pending/missing)
  with appropriate guidance text.

- REQ-P0-007: Contract test script test-proof-chain.sh covers full enforcement chain (#43).
  Acceptance: 18 test cases covering guard.sh Check 8, track.sh invalidation,
  session-init.sh clearing, and meta-repo exemptions. All tests pass in isolated temp dir.

- REQ-P0-008: HOOKS.md session-init.sh description mentions proof clearing (#44 residual).
  Acceptance: HOOKS.md line for session-init.sh includes "Clears stale .proof-status" language.

- REQ-P0-009: Test suite has 0 failures on main.
  Acceptance: tests/run-hooks.sh reports 0 failed. Crash detection test sources source-lib.sh.

- REQ-P0-010: guard.sh has no remaining dead rewrite() calls (#92 final sweep).
  Acceptance: grep -c 'rewrite ' hooks/guard.sh returns 0. All converted to deny().

### Nice-to-Have (P1)

- REQ-P1-001: Shared library consolidation — session lookup unified in context-lib.sh (#7).
- REQ-P1-002: compact-preserve.sh sources context-lib.sh instead of reimplementing (#7).
- REQ-P1-003: Raw jq calls converted to get_field() across 9 hooks (#7).
- REQ-P1-004: Self-audit harness consistency checks (#35) — evaluate /uplevel extension.
- REQ-P1-005: Markdown link verification in agent-written files (#93).

### Future Consideration (P2)

- REQ-P2-001: Multi-instance plan file scoping (#115) — project-scoped get_plan_file().
- REQ-P2-002: Hook status visualization with statusline (#94).
- REQ-P2-003: Checkpoint frequency auto-tuning (REQ-P1-002 from v2 plan).
- REQ-P2-004: Cross-session friction pattern detection (REQ-P1-003 from v2 plan).

## Definition of Done

All P0 requirements satisfied. Test suite at 0 failures. Auto-verify fires in production
on next clean tester run. Proof chain fully tested. Issues #41-44 closeable based on
evidence. Each phase independently valuable and mergeable.

## Architectural Decisions

- DEC-V3-001: Diagnostic-first approach for auto-verify repair.
  Addresses: REQ-P0-001, REQ-P0-002.
  Rationale: Auto-verify has never fired in production despite correct tester output.
  The root cause is unknown — could be payload truncation, wrong field name, or empty
  response text. Add diagnostic logging first to capture the actual payload structure,
  then fix based on evidence. Avoids speculative rewrites.

- DEC-V3-002: Convert remaining guard.sh rewrite() to deny() with suggested command.
  Addresses: REQ-P0-010.
  Rationale: updatedInput is not supported in PreToolUse hooks (upstream claude-code#26506).
  All rewrite() calls silently fail. The deny() approach forces the model to resubmit
  with the corrected command. UX cost is acceptable since upstream fix timeline is unknown.

- DEC-V3-003: Proof chain architecture has evolved — adapt #41-44 to current design.
  Addresses: REQ-P0-005, REQ-P0-006, REQ-P0-007, REQ-P0-008.
  Rationale: The original #41-44 plan assumed check-implementer.sh owned proof verification
  (Check 5). This was replaced by DEC-IMPL-STOP-001 which moved proof to the tester agent.
  The contract tests (#43) must be rewritten to reflect the current architecture: guard.sh
  Check 8 + Check 9 + Check 10, track.sh invalidation, task-track.sh Gate C, session-init.sh
  clearing. check-implementer.sh proof tests are no longer applicable.

- DEC-V3-004: Fix test crash detection by sourcing source-lib.sh in test subshell.
  Addresses: REQ-P0-009.
  Rationale: Test 6 in run-hooks.sh sources context-lib.sh directly but context-lib.sh
  calls get_claude_dir() which is defined in log.sh. The fix is to source source-lib.sh
  (which bootstraps log.sh + context-lib.sh) instead of sourcing context-lib.sh alone.

## Critical Files
- `hooks/check-tester.sh` — Auto-verify signal extraction (lines 89-159)
- `hooks/guard.sh` — Proof gate (Check 8), anti-tamper (Check 9-10), rewrite audit
- `hooks/track.sh` — Proof invalidation on source changes (lines 53-64)
- `hooks/session-summary.sh` — Missing proof status in stop output
- `hooks/subagent-start.sh` — Missing proof injection for implementer
- `hooks/context-lib.sh` — Shared library (2312 lines), session lookup duplication
- `tests/run-hooks.sh` — Test 6 crash detection failure, new test-proof-chain.sh

---

## Completed Phases (v2 Plan — archived)

Phases 0-5 from the v2 plan are completed and archived at
`archived-plans/2026-02-19_v2-governance-observability.md`. Summary:

| Phase | Name | Status | Issues |
|-------|------|--------|--------|
| 0 | Critical Fixes (Observatory Pipeline Revival) | completed | #99-#102 |
| 1 | Data Quality (Trace Accuracy) | completed | #103-#106 |
| 2 | Pipeline Completion (Observatory Enhancement) | completed | #107-#110 |
| 3 | v2 Session Event Log (Foundation) | completed | #81, #116, #117 |
| 4 | v2 Checkpoints & Rewind | completed | #82, #118-#120 |
| 5 | v2 Session-Aware Hooks + Commit Context | completed | #83, #84, #121, #122 |

---

## Phase 6: Auto-Verify Pipeline Repair
**Status:** planned
**Decision IDs:** DEC-V3-001, DEC-V3-004
**Requirements:** REQ-P0-001, REQ-P0-002, REQ-P0-003, REQ-P0-004, REQ-P0-009
**Issues:** #129, #121, #122, #125, #130, #131, #132, #133
**Definition of Done:**
- REQ-P0-001 satisfied: Auto-verify fires when tester signals AUTOVERIFY: CLEAN
- REQ-P0-002 satisfied: check-tester.sh diagnostic logging captures payload structure
- REQ-P0-003 satisfied: Guardian session context data flow validated by test
- REQ-P0-004 satisfied: INTENT-06 lifecycle test passes with 10 assertions
- REQ-P0-009 satisfied: Test suite reports 0 failures (crash detection test fixed)

### Planned Decisions
- DEC-V3-001: Diagnostic-first for auto-verify — add logging, observe payload, fix extraction — Addresses: REQ-P0-001, REQ-P0-002
- DEC-V3-004: Source source-lib.sh in test subshell to fix crash detection — Addresses: REQ-P0-009

### Work Items

**W6-1: Add diagnostic logging to check-tester.sh (#129)**
- check-tester.sh line 91 extracts RESPONSE_TEXT from `.last_assistant_message // .response`.
  The field may be truncated, empty, or use a different name.
- Add stderr logging: payload keys, RESPONSE_TEXT length, AUTOVERIFY grep result,
  secondary validation pass/fail details.
- Trigger: log on every SubagentStop:tester invocation so next tester run reveals the issue.

**W6-2: Fix auto-verify signal extraction based on diagnostics (#129)**
- After W6-1 logging reveals the payload structure, fix the extraction logic.
- Likely fix: field name mismatch, truncation handling, or multi-line grep.
- Must also verify secondary validation (confidence, coverage, caveats checks) works.

**W6-3: Guardian session context data flow test (#121)**
- Extend tests/test-session-context.sh with 2 new tests:
  1. Guardian injection path — source subagent-start.sh logic, verify SESSION_SUMMARY non-empty
  2. Stats accuracy — verify trajectory fields match known synthetic input (precise counts)

**W6-4: v2 lifecycle integration test INTENT-06 (#122)**
- Extend tests/test-v2-e2e.sh with 1 new intent test covering 10-stage lifecycle arc:
  session_start -> agent_start -> writes -> test_fail -> pivot detection ->
  checkpoint -> test_pass -> session_summary -> archive -> cross-session context.

**W6-5: Fix crash detection test failure**
- Test 6 in run-hooks.sh sources context-lib.sh directly. context-lib.sh calls
  get_claude_dir() from log.sh. Fix: source source-lib.sh instead.
- Also: commit the doc-freshness.sh chmod fix (#125) as part of this phase.

### Critical Files
- `hooks/check-tester.sh` — Auto-verify extraction (lines 89-159), diagnostic logging
- `tests/run-hooks.sh` — Test 6 crash detection (lines 1515-1537)
- `tests/test-session-context.sh` — Guardian injection tests
- `tests/test-v2-e2e.sh` — Lifecycle integration test INTENT-06

### Decision Log
<!-- Guardian appends here after phase completion -->


## Phase 7: Proof-of-Work Chain Completion
**Status:** planned
**Decision IDs:** DEC-V3-003
**Requirements:** REQ-P0-005, REQ-P0-006, REQ-P0-007, REQ-P0-008, REQ-P0-010
**Issues:** #41, #42, #43, #44, #92, #134, #135, #136
**Definition of Done:**
- REQ-P0-005 satisfied: session-summary.sh reports proof status
- REQ-P0-006 satisfied: subagent-start.sh injects proof status for implementer
- REQ-P0-007 satisfied: test-proof-chain.sh passes all test cases
- REQ-P0-008 satisfied: HOOKS.md session-init.sh description mentions proof clearing
- REQ-P0-010 satisfied: guard.sh has 0 rewrite() calls remaining

### Planned Decisions
- DEC-V3-003: Adapt #41-44 to current architecture (tester owns proof, not implementer) — Addresses: REQ-P0-005, REQ-P0-006, REQ-P0-007, REQ-P0-008

### Work Items

**W7-1: Add proof status to session-summary.sh (#42 residual)**
- After the GIT_LINE test status block (line 137), add proof status:
  Read .proof-status file. Append "Proof: verified." / "Proof: PENDING." / "Proof: not started."
- 5 lines of code.

**W7-2: Add proof status injection to subagent-start.sh (#42 residual)**
- Under the `implementer)` case, after the existing proof-status instruction (line 103):
  Read .proof-status and inject current status with contextual guidance.
  - verified: "Proof: verified -- user confirmed feature works."
  - pending: "WARNING: Proof PENDING -- source changed after last verification."
  - missing: "Proof: not started -- Phase 4 is REQUIRED before commit."
- 10 lines of code.

**W7-3: Write test-proof-chain.sh contract tests (#43, adapted)**
- Adapted from original 18-test plan. Revised for current architecture:
  - guard.sh Check 8: deny commit without verified (4 tests: no-file, pending, verified, meta-repo)
  - guard.sh Check 9: deny Bash writes to .proof-status (2 tests: block write, allow non-write)
  - guard.sh Check 10: deny deletion of active .proof-status (2 tests: block pending delete, allow verified delete)
  - track.sh invalidation: verified->pending on source change (4 tests: source/test/doc/already-pending)
  - task-track.sh Gate C: Guardian requires verified when file exists (3 tests: verified/pending/missing)
  - session-init.sh clearing: stale .proof-status cleaned at start (2 tests: cleaned/no-error)
  - session-summary.sh proof reporting (1 test: proof line present)
- Total: 18 tests in isolated temp git repo. TAP-compatible output.

**W7-4: Update HOOKS.md documentation (#44 residual)**
- session-init.sh description: add "Clears stale .proof-status (crash recovery)"
- Verify all other HOOKS.md proof-related documentation is accurate (spot-check done in
  planning phase — .proof-status state file row, check-implementer.sh description,
  guard.sh Checks 8-10 documentation all accurate).

**W7-5: Final guard.sh rewrite() audit (#92)**
- Grep for remaining rewrite() calls. #98 converted Check 1 (/tmp) and Check 3 (--force).
- Verify Check 0.5 (CWD recovery) and Check 5/5b (worktree deletion) are also converted.
- Confirm 0 rewrite() calls remain. Close #92.

### #41-44 Disposition

Based on comprehensive codebase audit (2026-02-19):

**#41 — Phase 1: Audit proof-of-work chain links**
- guard.sh Check 8: DONE and working (worktree fallback, meta-repo exemption, commit+merge).
- check-implementer.sh Check 5: ARCHITECTURE CHANGED. DEC-IMPL-STOP-001 moved proof to
  tester agent. check-implementer.sh has no proof check by design (builder/judge separation).
- track.sh invalidation: DONE and working (verified->pending on source, skips tests/docs).
- HOOKS.md discrepancy: DONE. Accurately reflects advisory-only + tester-moved proof.
- **Remaining**: Contract tests (acceptance criteria never written). Addressed by W7-3.
- **Close when**: W7-3 test-proof-chain.sh passes.

**#42 — Phase 2: Fill session lifecycle gaps for proof status**
- session-init.sh proof clearing: DONE (lines 355-368, crash recovery path).
- session-summary.sh proof reporting: NOT DONE. Addressed by W7-1.
- subagent-start.sh proof injection: PARTIALLY DONE (tells implementer not to write,
  but doesn't inject current status). Addressed by W7-2.
- **Close when**: W7-1 and W7-2 merged plus W7-3 covers session lifecycle tests.

**#43 — Phase 3: Contract test for proof-of-work chain**
- test-proof-chain.sh: NOT DONE. File does not exist.
- Original 18-test plan needs adaptation (no check-implementer.sh proof tests,
  add Check 9/10 and task-track.sh Gate C tests). Addressed by W7-3.
- **Close when**: W7-3 merged with all 18 tests passing.

**#44 — Phase 4: Documentation and HOOKS.md accuracy**
- HOOKS.md check-implementer.sh: DONE. Accurately says "Advisory only...moved to tester."
- HOOKS.md .proof-status state file: DONE. Complete lifecycle documented.
- HOOKS.md session-init.sh proof clearing: NOT DONE. Addressed by W7-4.
- CLAUDE.md Sacred Practice #10: DONE. Accurate.
- CLAUDE.md pre-dispatch gate: DONE. task-track.sh Gate C is blocking (deny).
- **Close when**: W7-4 merged.

### Critical Files
- `hooks/session-summary.sh` — Proof status addition (after line 137)
- `hooks/subagent-start.sh` — Proof injection for implementer (after line 103)
- `hooks/guard.sh` — rewrite() audit, Checks 8-10
- `hooks/task-track.sh` — Gate C (Guardian proof requirement)
- `tests/test-proof-chain.sh` — New file: 18 contract tests
- `hooks/HOOKS.md` — session-init.sh description update

### Decision Log
<!-- Guardian appends here after phase completion -->


## Phase 8: Shared Library Consolidation
**Status:** planned
**Decision IDs:** DEC-V3-005
**Requirements:** REQ-P1-001, REQ-P1-002, REQ-P1-003
**Issues:** #7, #137
**Definition of Done:**
- Session file lookup consolidated into context-lib.sh (one implementation, 4 callers)
- compact-preserve.sh sources context-lib.sh (no inline reimplementation)
- 9 hooks converted from raw jq to get_field()
- All existing tests continue to pass

### Planned Decisions
- DEC-V3-005: Mechanical refactoring with zero behavioral change — Addresses: REQ-P1-001, REQ-P1-002, REQ-P1-003
  Rationale: All changes are structural (function calls replace inline code). No logic changes.
  The shared library version of get_session_changes() is the weakest implementation — the
  inline copies in compact-preserve.sh and surface.sh have glob fallback and legacy support
  that the shared version lacks. Port the robust version into context-lib.sh, then replace
  all inline copies.

### Work Items

**W8-1: Port robust session lookup into context-lib.sh**
- compact-preserve.sh (lines 43-56) has the most robust implementation: glob fallback + legacy
  .session-decisions support. Port this into get_session_changes() in context-lib.sh.
- Replace inline implementations in: compact-preserve.sh, surface.sh, session-summary.sh.

**W8-2: Refactor compact-preserve.sh to source context-lib.sh**
- compact-preserve.sh is the only hook that reimplements context-lib equivalent operations.
- Replace 3 inline blocks with: get_git_state(), get_plan_status(), get_session_changes().
- Keep COMMIT_COUNT as a one-liner supplement (not in shared lib).

**W8-3: Convert raw jq to get_field() across 9 hooks**
- Affected: code-review.sh, plan-validate.sh, test-runner.sh, plan-check.sh (partially),
  notify.sh, forward-motion.sh, subagent-start.sh, surface.sh, session-summary.sh,
  prompt-submit.sh.
- Mechanical: `echo "$HOOK_INPUT" | jq -r '.field'` becomes `get_field "field"`.

**W8-4: Fix context-lib.sh permissions**
- chmod 755 (currently 644). All other .sh files are 755. Sourced not executed, but inconsistent.

**W8-5: Fix session-summary.sh SOURCE_EXTENSIONS hardcode**
- Line 64 hardcodes the extension list. context-lib.sh exports $SOURCE_EXTENSIONS.
- Replace hardcoded string with variable reference.

### Critical Files
- `hooks/context-lib.sh` — get_session_changes() upgrade, SOURCE_EXTENSIONS export
- `hooks/compact-preserve.sh` — Refactor to source context-lib.sh
- `hooks/surface.sh` — Replace inline session lookup
- `hooks/log.sh` — get_field() function (already exists, just need consumers)

### Decision Log
<!-- Guardian appends here after phase completion -->


## Worktree Strategy

Main is sacred. Each phase works in its own worktree:
- **Phase 6:** `~/.claude/.worktrees/v3-auto-verify` on branch `fix/auto-verify-pipeline`
- **Phase 7:** `~/.claude/.worktrees/v3-proof-chain` on branch `fix/proof-chain-completion`
- **Phase 8:** `~/.claude/.worktrees/v3-shared-lib` on branch `refactor/shared-library`

Implementation order: Phase 6 first (auto-verify is the highest-impact reliability gap),
then Phase 7 (proof chain depends on understanding payload structure from Phase 6 diagnostics),
then Phase 8 (pure refactoring, no behavioral change, lowest risk).

Stale worktrees to clean before starting: feature/guard-fix, feature/v2-session-hooks
(both merged, clean — Guardian should remove on first dispatch).

## References

### State Files
| File | Scope | Written By | Read By |
|------|-------|-----------|---------|
| `.proof-status` | Cross-session | task-track.sh (creates), tester (writes pending), prompt-submit.sh/check-tester.sh (writes verified), track.sh (invalidates) | guard.sh, task-track.sh, session-init.sh, session-summary.sh (planned), subagent-start.sh (planned) |
| `.session-events.jsonl` | Session | track.sh, guard.sh, checkpoint.sh | context-lib.sh, session-summary.sh |
| `.test-status` | Cross-session | test-runner.sh | guard.sh, test-gate.sh, session-summary.sh, check-implementer.sh, check-guardian.sh, subagent-start.sh |

### Issue Cross-Reference
| Issue | Plan Item | Disposition |
|-------|-----------|-------------|
| #129 | W6-1, W6-2 | Auto-verify signal extraction fix |
| #130 | W6-1, W6-2 | Phase 6 tracking issue for auto-verify |
| #131 | W6-5 | Test suite fix + doc-freshness chmod |
| #132 | W6-3 | Guardian session context data flow test |
| #133 | W6-4 | v2 lifecycle integration test INTENT-06 |
| #125 | W6-5 | doc-freshness.sh chmod (already done, needs commit) |
| #121 | W6-3 | Guardian session context data flow test (original) |
| #122 | W6-4 | v2 lifecycle integration test INTENT-06 (original) |
| #134 | W7-1, W7-2 | Session lifecycle proof gaps |
| #135 | W7-3 | Contract test test-proof-chain.sh |
| #136 | W7-4, W7-5 | HOOKS.md accuracy + guard.sh rewrite sweep |
| #137 | W8-1 through W8-5 | Shared library consolidation |
| #41 | W7-3 | Proof chain audit — mostly done, needs contract tests |
| #42 | W7-1, W7-2 | Session lifecycle proof gaps — 2 items remaining |
| #43 | W7-3 | Contract test script — adapted for current architecture |
| #44 | W7-4 | HOOKS.md accuracy — 1 item remaining |
| #92 | W7-5 | guard.sh rewrite() final sweep |
| #7 | W8-1 through W8-5 | Shared library consolidation (original) |

### Parked Issues (not this plan)
| Issue | Reason |
|-------|--------|
| #115 | Multi-instance plan scoping — separate plan (touches 14+ hooks) |
| #94 | Hook status visualization — enhancement, not hardening |
| #93 | Link verification — P1, after hardening |
| #35 | Self-audit harness — P1, after hardening |
| #97/#96/#95 | Upstream-blocked |
| #46/#22/#17/#8 | Separate initiatives |
| #69/#67/#61/#57/#58 | todo.sh / standards — separate initiatives |
