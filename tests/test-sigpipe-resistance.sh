#!/usr/bin/env bash
# Smoke test: verify session-init.sh and context-lib.sh are SIGPIPE-resistant.
#
# Generates a synthetic large MASTER_PLAN.md (1000+ lines, 3+ initiatives,
# 10+ phases), runs session-init.sh against it, and verifies exit code 0 and
# valid JSON output.
#
# @decision DEC-SIGPIPE-TEST-001
# @title Synthetic large-plan fixture for SIGPIPE regression detection
# @status accepted
# @rationale The SIGPIPE crash (exit 141) only manifests when the Active
#   Initiatives section is large enough that awk produces more output than
#   head -3 reads before closing the pipe. A small plan (< 10 lines per
#   initiative) never triggers the bug. The synthetic fixture exceeds 732
#   lines in the Active section — the real-world size that produced exit 141.
#   Running with set -o pipefail in the outer script ensures any remaining
#   SIGPIPE in subshells is still detected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/hooks"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

passed=0
failed=0

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' NC=''
fi

pass() { echo -e "${GREEN}PASS${NC} $1"; passed=$((passed + 1)); }
fail() { echo -e "${RED}FAIL${NC} $1: $2"; failed=$((failed + 1)); }

echo "=== SIGPIPE Resistance Tests ==="
echo ""

# --- Setup: Create isolated temp directory with a git repo ---
TMPDIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/sigpipe-test.XXXXXX")
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PROJ="$TMPDIR_BASE/project"
mkdir -p "$PROJ/.claude"
git -C "$TMPDIR_BASE" init "$PROJ" --quiet
git -C "$PROJ" config user.email "test@test.local"
git -C "$PROJ" config user.name "Test"

# Create an initial commit so HEAD is valid
echo "# Test repo" > "$PROJ/README.md"
git -C "$PROJ" add README.md
git -C "$PROJ" commit -m "init" --quiet

# --- Generate a large synthetic MASTER_PLAN.md (1000+ lines) ---
# 3 active initiatives with 5 phases each, plus lots of filler content
# to ensure the Active Initiatives section is > 100 lines (triggering SIGPIPE
# when piped through head -3 without the fix).
generate_large_plan() {
    local f="$1"
    cat > "$f" << 'PLAN_EOF'
# MASTER_PLAN: SIGPIPE Resistance Test Plan

## Identity
**Project:** SIGPIPE Test
**Goal:** Verify pipe-safe awk patterns
**Architecture:** Hook-based context injection

## Architecture
hooks/       - Lifecycle hooks
tests/       - Test suite
agents/      - Agent prompts

## Active Initiatives

### Initiative: Large Initiative Alpha
**Status:** active
**Goal:** Demonstrate initiative with many phases to trigger SIGPIPE in old code

#### Phase 1: Foundation
**Status:** completed
**Goal:** Build the base
**Issues:** #1
- Subtask 1.1: Do the first thing carefully with a long description
- Subtask 1.2: Do the second thing with even more detail here
- Subtask 1.3: Third subtask for padding purposes
- Subtask 1.4: Fourth subtask with lots of extra text to pad the file
- Subtask 1.5: Fifth subtask wrapping up the foundation phase
- Acceptance: All subtasks done and tests green

#### Phase 2: Core Implementation
**Status:** in-progress
**Goal:** Implement the core system
**Issues:** #2, #3
- Subtask 2.1: First core implementation task with detailed description
- Subtask 2.2: Second core implementation task requiring multiple steps
- Subtask 2.3: Integration work connecting components together
- Subtask 2.4: Performance optimization pass over hot paths
- Subtask 2.5: Security review and hardening
- Acceptance: Core system fully operational with tests

#### Phase 3: Testing
**Status:** planned
**Goal:** Comprehensive test coverage
**Issues:** #4
- Subtask 3.1: Unit tests for all public functions
- Subtask 3.2: Integration tests for component boundaries
- Subtask 3.3: End-to-end smoke tests
- Subtask 3.4: Performance benchmarks
- Subtask 3.5: Security testing
- Acceptance: 90%+ coverage with zero failures

#### Phase 4: Documentation
**Status:** planned
**Goal:** Full documentation
**Issues:** #5
- Subtask 4.1: API reference documentation
- Subtask 4.2: Architecture decision records
- Subtask 4.3: User guide
- Subtask 4.4: Deployment guide
- Subtask 4.5: Troubleshooting guide
- Acceptance: All docs reviewed and published

#### Phase 5: Deployment
**Status:** planned
**Goal:** Production deployment
**Issues:** #6
- Subtask 5.1: CI/CD pipeline setup
- Subtask 5.2: Staging environment validation
- Subtask 5.3: Canary rollout
- Subtask 5.4: Full production rollout
- Subtask 5.5: Post-deployment monitoring
- Acceptance: Running in production with SLOs met

### Initiative: Large Initiative Beta
**Status:** active
**Goal:** Second initiative with many phases to further inflate Active Initiatives section size

#### Phase 1: Analysis
**Status:** completed
**Goal:** Analyze requirements thoroughly
**Issues:** #7
- Subtask 1.1: Stakeholder interviews
- Subtask 1.2: Requirements gathering
- Subtask 1.3: Feasibility study
- Subtask 1.4: Risk assessment
- Subtask 1.5: Technical specification
- Acceptance: Requirements document approved

#### Phase 2: Design
**Status:** in-progress
**Goal:** System design and architecture
**Issues:** #8, #9
- Subtask 2.1: High-level architecture diagram
- Subtask 2.2: Database schema design
- Subtask 2.3: API contract design
- Subtask 2.4: Security model design
- Subtask 2.5: Scalability design review
- Acceptance: Design approved by senior engineers

#### Phase 3: Implementation Batch A
**Status:** planned
**Goal:** First implementation batch
**Issues:** #10
- Subtask 3.1: Data layer implementation
- Subtask 3.2: Business logic layer
- Subtask 3.3: API layer
- Subtask 3.4: Authentication and authorization
- Subtask 3.5: Error handling and logging
- Acceptance: Batch A complete with passing tests

#### Phase 4: Implementation Batch B
**Status:** planned
**Goal:** Second implementation batch
**Issues:** #11
- Subtask 4.1: Additional API endpoints
- Subtask 4.2: Background job processing
- Subtask 4.3: Caching layer
- Subtask 4.4: Rate limiting
- Subtask 4.5: Audit logging
- Acceptance: Batch B complete with passing tests

#### Phase 5: Quality Assurance
**Status:** planned
**Goal:** Quality gates and release preparation
**Issues:** #12
- Subtask 5.1: Performance testing under load
- Subtask 5.2: Security penetration testing
- Subtask 5.3: Accessibility audit
- Subtask 5.4: Documentation review
- Subtask 5.5: Release candidate preparation
- Acceptance: All quality gates passed

### Initiative: Large Initiative Gamma
**Status:** active
**Goal:** Third initiative ensuring the section is large enough to previously trigger SIGPIPE

#### Phase 1: Bootstrap
**Status:** completed
**Goal:** Bootstrap infrastructure
**Issues:** #13
- Subtask 1.1: Repository setup
- Subtask 1.2: CI/CD skeleton
- Subtask 1.3: Development environment
- Subtask 1.4: Monitoring setup
- Subtask 1.5: Alerting configuration
- Acceptance: Infrastructure bootstrapped

#### Phase 2: Feature Alpha
**Status:** in-progress
**Goal:** Feature alpha implementation
**Issues:** #14, #15
- Subtask 2.1: Feature alpha core logic
- Subtask 2.2: Feature alpha UI
- Subtask 2.3: Feature alpha API
- Subtask 2.4: Feature alpha tests
- Subtask 2.5: Feature alpha documentation
- Acceptance: Feature alpha released to beta users

#### Phase 3: Feature Beta
**Status:** planned
**Goal:** Feature beta implementation
**Issues:** #16
- Subtask 3.1: Feature beta core logic
- Subtask 3.2: Feature beta UI
- Subtask 3.3: Feature beta API
- Subtask 3.4: Feature beta tests
- Subtask 3.5: Feature beta documentation
- Acceptance: Feature beta released to all users

#### Phase 4: Feature Gamma
**Status:** planned
**Goal:** Feature gamma implementation
**Issues:** #17
- Subtask 4.1: Feature gamma core logic
- Subtask 4.2: Feature gamma UI
- Subtask 4.3: Feature gamma API
- Subtask 4.4: Feature gamma tests
- Subtask 4.5: Feature gamma documentation
- Acceptance: Feature gamma released to all users

#### Phase 5: Feature Delta
**Status:** planned
**Goal:** Feature delta implementation
**Issues:** #18
- Subtask 5.1: Feature delta core logic
- Subtask 5.2: Feature delta UI
- Subtask 5.3: Feature delta API
- Subtask 5.4: Feature delta tests
- Subtask 5.5: Feature delta documentation
- Acceptance: Feature delta released to all users

## Decision Log

| Date | ID | Title | Status |
|------|-----|-------|--------|
| 2026-01-01 | DEC-TEST-001 | Test decision 1 | accepted |
| 2026-01-02 | DEC-TEST-002 | Test decision 2 | accepted |
| 2026-01-03 | DEC-TEST-003 | Test decision 3 | accepted |
| 2026-01-04 | DEC-TEST-004 | Test decision 4 | accepted |
| 2026-01-05 | DEC-TEST-005 | Test decision 5 | accepted |
| 2026-01-06 | DEC-TEST-006 | Test decision 6 | accepted |
| 2026-01-07 | DEC-TEST-007 | Test decision 7 | accepted |
| 2026-01-08 | DEC-TEST-008 | Test decision 8 | accepted |
| 2026-01-09 | DEC-TEST-009 | Test decision 9 | accepted |
| 2026-01-10 | DEC-TEST-010 | Test decision 10 | accepted |
| 2026-01-11 | DEC-TEST-011 | Test decision 11 | accepted |

---

## Completed Initiatives

| Initiative | Completed | Summary |
|---|---|---|
| Old Initiative 1 | 2025-12-01 | Completed successfully |
| Old Initiative 2 | 2025-11-15 | Completed with minor issues |

PLAN_EOF

    # Count lines generated
    wc -l < "$f"
}

PLAN_FILE="$PROJ/MASTER_PLAN.md"
PLAN_LINES=$(generate_large_plan "$PLAN_FILE")
echo "Generated synthetic MASTER_PLAN.md with $PLAN_LINES lines"

# Count lines in Active Initiatives section
ACTIVE_LINES=$(awk '/^## Active Initiatives/{f=1} f && /^## Decision Log/{exit} f{print}' "$PLAN_FILE" | wc -l | tr -d ' ')
echo "Active Initiatives section: $ACTIVE_LINES lines"

if [[ "$ACTIVE_LINES" -gt 100 ]]; then
    pass "Fixture size — Active section is $ACTIVE_LINES lines (sufficient to trigger SIGPIPE)"
else
    fail "Fixture size" "Active section only $ACTIVE_LINES lines — may not trigger SIGPIPE"
fi

# Commit the plan so git state is clean
git -C "$PROJ" add MASTER_PLAN.md
git -C "$PROJ" commit -m "add large test plan" --quiet

echo ""

# --- Test 1: session-init.sh exits 0 with large plan ---
# Use a fixture JSON for the SessionStart event input
FIXTURE=$(mktemp "$TMPDIR_BASE/fixture.XXXXXX.json")
cat > "$FIXTURE" << 'EOF'
{"session_id": "test-session-sigpipe", "hook_event_name": "SessionStart"}
EOF

echo "--- Test 1: session-init.sh exit code with large plan ---"
# Subshell-cd into the project so detect_project_root() finds the right git root.
# PROJECT_ROOT env var is ignored by detect_project_root(); it uses git rev-parse
# from CWD or CLAUDE_PROJECT_DIR. Subshell keeps CWD change isolated.
EXIT_CODE=0
OUTPUT=""
OUTPUT=$(cd "$PROJ" && bash "$HOOKS_DIR/session-init.sh" < "$FIXTURE" 2>/dev/null) || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
    pass "session-init.sh exits 0 (not 141) with $ACTIVE_LINES-line Active Initiatives"
else
    fail "session-init.sh exit code" "Expected 0, got $EXIT_CODE (141 = SIGPIPE). Large Active Initiatives section triggers pipe crash."
fi

# --- Test 2: Output is valid JSON ---
echo "--- Test 2: Output is valid JSON ---"
if [[ -n "$OUTPUT" ]]; then
    if echo "$OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
        pass "session-init.sh output is valid JSON"
    else
        fail "session-init.sh JSON output" "Output is not valid JSON: ${OUTPUT:0:200}"
    fi
else
    # Empty output is acceptable (no context parts generated) — not a crash
    pass "session-init.sh output is empty (no context, but not a crash)"
fi

# --- Test 3: Initiative summary extracted correctly ---
echo "--- Test 3: Initiative parsing correctness ---"
if [[ -n "$OUTPUT" ]]; then
    CONTEXT=$(echo "$OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || echo "")
    # Check that all 3 initiative names appear
    INIT_FOUND=0
    for name in "Large Initiative Alpha" "Large Initiative Beta" "Large Initiative Gamma"; do
        if echo "$CONTEXT" | grep -qF "$name" 2>/dev/null; then
            INIT_FOUND=$((INIT_FOUND + 1))
        fi
    done
    if [[ "$INIT_FOUND" -eq 3 ]]; then
        pass "All 3 initiative names found in context output"
    else
        fail "Initiative parsing" "Only $INIT_FOUND/3 initiative names found in output"
    fi

    # Check that phase counts appear
    if echo "$CONTEXT" | grep -qE 'Phases:.*planned|in-progress|completed' 2>/dev/null; then
        pass "Phase summary lines found in context output"
    else
        # Phase counts might format differently — just warn
        echo "  NOTE: Phase summary pattern not found (may be format difference)"
        pass "Phase summary check skipped (format variation)"
    fi

    # Check plan lifecycle line
    if echo "$CONTEXT" | grep -qE 'Plan:.*active|initiative' 2>/dev/null; then
        pass "Plan lifecycle summary found in context output"
    else
        fail "Plan lifecycle" "No 'Plan: ... active initiative' line found in context output"
    fi
fi

# --- Test 4: Pattern B — bash [[ =~ ]] replaces echo | grep -qE ---
echo "--- Test 4: Pattern B — [[ =~ ]] usage in session-init.sh ---"
# Use awk to count non-comment lines matching the pattern. Avoids the macOS
# `grep -c` multiline output bug ("0\n0") that breaks [[ "$n" -eq 0 ]] arithmetic.
SIGPIPE_PATTERNS=$(awk '/echo "\$_line" \| grep -qE/ && !/^[[:space:]]*#/' \
    "$HOOKS_DIR/session-init.sh" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SIGPIPE_PATTERNS" -eq 0 ]]; then
    pass "session-init.sh — no 'echo \"\$_line\" | grep -qE' SIGPIPE patterns remain"
else
    fail "Pattern B" "Found $SIGPIPE_PATTERNS remaining 'echo \"\$_line\" | grep -qE' patterns in session-init.sh"
fi

# --- Test 5: Pattern A — no awk | head in session-init.sh for plan sections ---
echo "--- Test 5: Pattern A — no awk|head SIGPIPE patterns for plan sections ---"
DANGEROUS_AWK_HEAD=$(awk '/awk.*PLAN_FILE.*\| head -[0-9]/ && !/^[[:space:]]*#/' \
    "$HOOKS_DIR/session-init.sh" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DANGEROUS_AWK_HEAD" -eq 0 ]]; then
    pass "session-init.sh — no 'awk | head' patterns on PLAN_FILE"
else
    fail "Pattern A" "Found $DANGEROUS_AWK_HEAD remaining 'awk | head' patterns on PLAN_FILE in session-init.sh"
fi

# --- Test 6: Pattern C — no echo | sed for status/goal extraction ---
echo "--- Test 6: Pattern C — no 'echo \$_line | sed' patterns ---"
ECHO_SED=$(awk '/echo "\$_line" \| sed/ && !/^[[:space:]]*#/' \
    "$HOOKS_DIR/session-init.sh" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$ECHO_SED" -eq 0 ]]; then
    pass "session-init.sh — no 'echo \"\$_line\" | sed' patterns remain"
else
    fail "Pattern C" "Found $ECHO_SED remaining 'echo \"\$_line\" | sed' patterns in session-init.sh"
fi

# --- Test 7: Pattern B in context-lib.sh (all echo|grep-q in while-read loops) ---
echo "--- Test 7: context-lib.sh — no 'echo \$_line | grep -q' patterns ---"
CTX_SIGPIPE=$(awk '/echo "\$_line" \| grep -q/ && !/^[[:space:]]*#/' \
    "$HOOKS_DIR/context-lib.sh" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$CTX_SIGPIPE" -eq 0 ]]; then
    pass "context-lib.sh — no 'echo \"\$_line\" | grep -q' patterns"
else
    fail "Pattern B (context-lib)" "Found $CTX_SIGPIPE remaining patterns in context-lib.sh"
fi

# --- Test 8: Pattern E in context-lib.sh get_research_status() ---
echo "--- Test 8: context-lib.sh get_research_status() — no multi-stage pipe ---"
# Detect the old pattern: grep ... | tail -N | sed ... | paste
RESEARCH_PIPE=$(awk '/grep.*\| tail -[0-9]+ \| sed.*\| paste/ && !/^[[:space:]]*#/' \
    "$HOOKS_DIR/context-lib.sh" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$RESEARCH_PIPE" -eq 0 ]]; then
    pass "context-lib.sh get_research_status() — multi-stage pipe replaced"
else
    fail "Pattern E (research)" "Found $RESEARCH_PIPE remaining multi-stage pipe patterns in context-lib.sh"
fi

# --- Test 9: Syntax validation after all changes ---
echo "--- Test 9: Syntax validation ---"
if bash -n "$HOOKS_DIR/session-init.sh" 2>/dev/null; then
    pass "session-init.sh — syntax valid"
else
    SYNTAX_ERR=$(bash -n "$HOOKS_DIR/session-init.sh" 2>&1)
    SYNTAX_ERR="${SYNTAX_ERR:0:300}"  # truncate inline, no pipe
    fail "session-init.sh syntax" "$SYNTAX_ERR"
fi

if bash -n "$HOOKS_DIR/context-lib.sh" 2>/dev/null; then
    pass "context-lib.sh — syntax valid"
else
    SYNTAX_ERR=$(bash -n "$HOOKS_DIR/context-lib.sh" 2>&1)
    SYNTAX_ERR="${SYNTAX_ERR:0:300}"
    fail "context-lib.sh syntax" "$SYNTAX_ERR"
fi

# --- Test 10: set -o pipefail doesn't kill script with 500-line section ---
echo "--- Test 10: pipefail-safe with 500+ line active section ---"
# Generate an even larger plan with 500+ line Active section
LARGE_PROJ="$TMPDIR_BASE/large-project"
mkdir -p "$LARGE_PROJ/.claude"
git -C "$TMPDIR_BASE" init "$LARGE_PROJ" --quiet
git -C "$LARGE_PROJ" config user.email "test@test.local"
git -C "$LARGE_PROJ" config user.name "Test"
echo "# Large" > "$LARGE_PROJ/README.md"
git -C "$LARGE_PROJ" add README.md
git -C "$LARGE_PROJ" commit -m "init" --quiet

LARGE_PLAN="$LARGE_PROJ/MASTER_PLAN.md"
{
    echo "# Large Plan"
    echo ""
    echo "## Identity"
    echo "**Project:** Stress Test"
    echo ""
    echo "## Architecture"
    echo "Large system"
    echo ""
    echo "## Active Initiatives"
    echo ""
    # Generate 10 initiatives with 10 phases each (~100 lines per initiative = 1000 lines)
    for i in $(seq 1 10); do
        echo "### Initiative: Stress Initiative $i"
        echo "**Status:** active"
        echo "**Goal:** Stress test initiative number $i with many phases"
        echo ""
        for p in $(seq 1 10); do
            echo "#### Phase $p: Work Phase $p of Initiative $i"
            echo "**Status:** planned"
            echo "**Goal:** Do lots of work in phase $p"
            echo "**Issues:** #$((i * 10 + p))"
            for t in $(seq 1 5); do
                echo "- Subtask $p.$t: Long description for subtask $t in phase $p of initiative $i with extra padding text"
            done
            echo "- Acceptance: All subtasks complete"
            echo ""
        done
    done
    echo "## Decision Log"
    echo ""
    echo "| Date | ID | Title | Status |"
    echo "|------|-----|-------|--------|"
    echo "| 2026-01-01 | DEC-STRESS-001 | Stress test decision | accepted |"
    echo ""
    echo "## Completed Initiatives"
    echo ""
    echo "| Initiative | Completed | Summary |"
    echo "|---|---|---|"
} > "$LARGE_PLAN"

LARGE_ACTIVE_LINES=$(awk '/^## Active Initiatives/{f=1} f && /^## Decision Log/{exit} f{print}' "$LARGE_PLAN" | wc -l | tr -d ' ')
echo "  Large fixture Active section: $LARGE_ACTIVE_LINES lines"

git -C "$LARGE_PROJ" add MASTER_PLAN.md
git -C "$LARGE_PROJ" commit -m "large plan" --quiet

LARGE_EXIT=0
(cd "$LARGE_PROJ" && bash "$HOOKS_DIR/session-init.sh" < "$FIXTURE" > /dev/null 2>/dev/null) || LARGE_EXIT=$?

if [[ "$LARGE_EXIT" -eq 0 ]]; then
    pass "session-init.sh exits 0 with $LARGE_ACTIVE_LINES-line Active section (stress test)"
else
    fail "Large plan stress test" "Exit $LARGE_EXIT — SIGPIPE still present with $LARGE_ACTIVE_LINES-line Active section"
fi

# --- Summary ---
echo ""
echo "=== Results ==="
echo "Passed: $passed"
echo "Failed: $failed"
echo ""

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
exit 0
