#!/usr/bin/env bash
# test-observatory-signals-v2.sh — Tests for 7 new Observatory signals
#
# Purpose: Verify the 7 new signals (SIG-MAIN-IMPL, SIG-BRANCH-UNKNOWN,
#          SIG-AGENT-TYPE-MISMATCH, SIG-CRASH-CLUSTER, SIG-STALE-MARKERS,
#          SIG-PROOF-UNKNOWN) are correctly detected or absent
#          based on controlled fixture data. Each test uses an isolated temp dir.
#
# @decision DEC-OBS-016
# @title Fixture-based signal detection tests with isolated temp dirs
# @status accepted
# @rationale Each signal test creates its own temp environment with controlled
#             trace index data so tests are fully isolated and deterministic.
#             Real trace data cannot guarantee the conditions needed to
#             trigger or suppress specific signals. Fixtures are controlled
#             inputs, not mocks of internal logic.
#
# Usage: bash tests/observatory/test-observatory-signals-v2.sh
# Returns: 0 if all tests pass, 1 if any fail

set -euo pipefail

WORKTREE="${HOME}/.claude/.worktrees/observatory-signals-v2"
ANALYZE_SCRIPT="${WORKTREE}/skills/observatory/scripts/analyze.sh"
SUGGEST_SCRIPT="${WORKTREE}/skills/observatory/scripts/suggest.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Create a fresh isolated temp environment for each test
setup_env() {
    local tmp_dir
    tmp_dir=$(mktemp -d "${WORKTREE}/tmp/test-sig-v2-XXXXXX")
    local obs_dir="${tmp_dir}/observatory"
    local trace_store="${tmp_dir}/traces"
    mkdir -p "$obs_dir" "$trace_store"
    echo "$tmp_dir"
}

# Write a minimal valid trace index entry
# Args: implementer/planner/etc, outcome, branch, agent_type, duration, files_changed
make_entry() {
    local agent="${1:-implementer}"
    local outcome="${2:-success}"
    local branch="${3:-main}"
    local agent_type="${4:-implementer}"
    local duration="${5:-120}"
    local files="${6:-5}"
    printf '{"session_id":"test-%s","agent_type":"%s","outcome":"%s","branch":"%s","duration_seconds":%s,"files_changed":%s,"test_result":"pass","started_at":"2026-02-17T00:00:00Z","completed_at":"2026-02-17T00:02:00Z"}\n' \
        "$RANDOM" "$agent_type" "$outcome" "$branch" "$duration" "$files"
}

# ============================================================
# TEST 1: SIG-MAIN-IMPL — implementer on main/master branch
# ============================================================
echo ""
echo "=== Test 1: SIG-MAIN-IMPL detected when implementer runs on main ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # Write index: 1 implementer on main, 2 implementers on feature branch
    make_entry "implementer" "success" "main" "implementer" 120 5 > "${trace_store}/index.jsonl"
    make_entry "implementer" "success" "feature/foo" "implementer" 120 5 >> "${trace_store}/index.jsonl"
    make_entry "implementer" "success" "feature/foo" "implementer" 120 5 >> "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-MAIN-IMPL") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-MAIN-IMPL" ]]; then
        # Also check affected_count = 1
        COUNT=$(jq '.improvement_signals[] | select(.id == "SIG-MAIN-IMPL") | .evidence.affected_count' "${obs_dir}/analysis-cache.json")
        if [[ "$COUNT" -eq 1 ]]; then
            pass "SIG-MAIN-IMPL detected with affected_count=1"
        else
            fail "SIG-MAIN-IMPL detected but affected_count=$COUNT (expected 1)"
        fi
    else
        fail "SIG-MAIN-IMPL not detected for implementer on main branch"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 2: SIG-BRANCH-UNKNOWN — traces with branch="unknown"
# ============================================================
echo ""
echo "=== Test 2: SIG-BRANCH-UNKNOWN detected when branch='unknown' ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    make_entry "planner" "success" "unknown" "planner" 60 0 > "${trace_store}/index.jsonl"
    make_entry "planner" "success" "feature/x" "planner" 60 3 >> "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-BRANCH-UNKNOWN") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-BRANCH-UNKNOWN" ]]; then
        pass "SIG-BRANCH-UNKNOWN detected"
    else
        fail "SIG-BRANCH-UNKNOWN not detected for branch='unknown'"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 3: SIG-AGENT-TYPE-MISMATCH — agent_type="Plan" (capital P)
# ============================================================
echo ""
echo "=== Test 3: SIG-AGENT-TYPE-MISMATCH detected when agent_type='Plan' ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # 2 entries with wrongly-capitalized "Plan"
    make_entry "planner" "success" "feature/y" "Plan" 60 0 > "${trace_store}/index.jsonl"
    make_entry "planner" "success" "feature/y" "Plan" 60 0 >> "${trace_store}/index.jsonl"
    make_entry "planner" "success" "feature/y" "planner" 60 3 >> "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-AGENT-TYPE-MISMATCH") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-AGENT-TYPE-MISMATCH" ]]; then
        COUNT=$(jq '.improvement_signals[] | select(.id == "SIG-AGENT-TYPE-MISMATCH") | .evidence.affected_count' "${obs_dir}/analysis-cache.json")
        if [[ "$COUNT" -eq 2 ]]; then
            pass "SIG-AGENT-TYPE-MISMATCH detected with affected_count=2"
        else
            fail "SIG-AGENT-TYPE-MISMATCH detected but affected_count=$COUNT (expected 2)"
        fi
    else
        fail "SIG-AGENT-TYPE-MISMATCH not detected for agent_type='Plan'"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 4: SIG-CRASH-CLUSTER — agent type with >50% crash rate AND >5 traces
# ============================================================
echo ""
echo "=== Test 4: SIG-CRASH-CLUSTER detected when agent type >50% crash rate with >5 traces ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # 6 general-purpose traces, 5 crashed (83% crash rate) — should trigger
    {
        for i in 1 2 3 4 5; do
            make_entry "general-purpose" "crashed" "main" "general-purpose" 30 0
        done
        make_entry "general-purpose" "success" "main" "general-purpose" 120 5
        # Add some planner traces with good rates (should not trigger)
        make_entry "planner" "success" "feature/a" "planner" 60 3
        make_entry "planner" "success" "feature/b" "planner" 60 3
    } > "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-CRASH-CLUSTER") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-CRASH-CLUSTER" ]]; then
        AGENTS=$(jq -r '.improvement_signals[] | select(.id == "SIG-CRASH-CLUSTER") | .evidence.crash_cluster_agents' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "[]")
        pass "SIG-CRASH-CLUSTER detected (agents: $AGENTS)"
    else
        fail "SIG-CRASH-CLUSTER not detected for agent type with >50% crash rate and >5 traces"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 5: SIG-STALE-MARKERS — orphaned .active-* files
# ============================================================
echo ""
echo "=== Test 5: SIG-STALE-MARKERS detected for orphaned .active-* files ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # Normal index
    make_entry "implementer" "success" "feature/z" "implementer" 120 5 > "${trace_store}/index.jsonl"

    # Create a stale .active-* file in TRACE_STORE
    touch "${trace_store}/.active-implementer-dead-session"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-STALE-MARKERS") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-STALE-MARKERS" ]]; then
        COUNT=$(jq '.improvement_signals[] | select(.id == "SIG-STALE-MARKERS") | .evidence.affected_count' "${obs_dir}/analysis-cache.json")
        pass "SIG-STALE-MARKERS detected with affected_count=$COUNT"
    else
        fail "SIG-STALE-MARKERS not detected for orphaned .active-* file"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 6: SIG-PROOF-UNKNOWN — >80% manifests have proof_status unknown/missing
# ============================================================
echo ""
echo "=== Test 6: SIG-PROOF-UNKNOWN detected when >80% manifests have unknown proof_status ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # Create 5 trace directories with manifests
    # 4 have unknown proof_status (80%), 1 has verified
    for i in 1 2 3 4; do
        trace_dir="${trace_store}/trace-00${i}"
        mkdir -p "${trace_dir}/artifacts"
        printf '{"proof_status":"unknown","session_id":"test-%s","agent_type":"implementer","outcome":"partial","started_at":"2026-02-17T00:00:00Z","completed_at":"2026-02-17T00:02:00Z","duration_seconds":120,"files_changed":0,"test_result":"unknown","branch":"feature/x"}\n' "$i" > "${trace_dir}/manifest.json"
    done
    trace_dir="${trace_store}/trace-005"
    mkdir -p "${trace_dir}/artifacts"
    printf '{"proof_status":"verified","session_id":"test-5","agent_type":"tester","outcome":"success","started_at":"2026-02-17T00:00:00Z","completed_at":"2026-02-17T00:02:00Z","duration_seconds":60,"files_changed":0,"test_result":"pass","branch":"feature/x"}\n' > "${trace_dir}/manifest.json"

    # Index must exist
    make_entry "implementer" "success" "feature/x" "implementer" 120 5 > "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-PROOF-UNKNOWN") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-PROOF-UNKNOWN" ]]; then
        pass "SIG-PROOF-UNKNOWN detected when 80% manifests have unknown proof_status"
    else
        # Show what signals fired for debugging
        SIGS=$(jq -r '.improvement_signals[].id' "${obs_dir}/analysis-cache.json" 2>/dev/null | tr '\n' ',' || echo "none")
        fail "SIG-PROOF-UNKNOWN not detected (signals: $SIGS)"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 7: Clean data — none of the 7 new signals emitted
# ============================================================
echo ""
echo "=== Test 7: Clean data — none of the 7 new signals emitted ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # All implementers on feature branches, proper agent_type, good outcomes
    {
        for i in 1 2 3 4 5 6; do
            make_entry "implementer" "success" "feature/clean-${i}" "implementer" 120 5
        done
        make_entry "planner" "success" "feature/plan-1" "planner" 60 3
        make_entry "tester" "success" "feature/test-1" "tester" 45 0
    } > "${trace_store}/index.jsonl"

    # Create trace dirs with verified proof_status (so SIG-PROOF-UNKNOWN doesn't fire)
    for i in 1 2 3; do
        trace_dir="${trace_store}/trace-clean-00${i}"
        mkdir -p "${trace_dir}/artifacts"
        printf '{"proof_status":"verified","session_id":"clean-%s","agent_type":"implementer","outcome":"success","started_at":"2026-02-17T00:00:00Z","completed_at":"2026-02-17T00:02:00Z","duration_seconds":120,"files_changed":5,"test_result":"pass","branch":"feature/clean"}\n' "$i" > "${trace_dir}/manifest.json"
    done

    # No .active-* files

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    NEW_SIGNALS=("SIG-MAIN-IMPL" "SIG-BRANCH-UNKNOWN" "SIG-AGENT-TYPE-MISMATCH" "SIG-CRASH-CLUSTER" "SIG-STALE-MARKERS" "SIG-PROOF-UNKNOWN")
    ALL_CLEAN=true
    for sig in "${NEW_SIGNALS[@]}"; do
        FOUND=$(jq -r --arg id "$sig" '.improvement_signals[] | select(.id == $id) | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
        if [[ -n "$FOUND" ]]; then
            fail "Signal $sig fired on clean data (should not)"
            ALL_CLEAN=false
        fi
    done
    if [[ "$ALL_CLEAN" == "true" ]]; then
        pass "No new signals emitted for clean trace data"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 8: SIG-MAIN-IMPL also detected for "master" branch
# ============================================================
echo ""
echo "=== Test 8: SIG-MAIN-IMPL also triggers for 'master' branch ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    make_entry "implementer" "success" "master" "implementer" 120 5 > "${trace_store}/index.jsonl"
    make_entry "implementer" "success" "feature/ok" "implementer" 120 5 >> "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-MAIN-IMPL") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ "$SIG" == "SIG-MAIN-IMPL" ]]; then
        pass "SIG-MAIN-IMPL detected for implementer on 'master' branch"
    else
        fail "SIG-MAIN-IMPL not detected for 'master' branch"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 9: SIG-CRASH-CLUSTER NOT triggered when count <= 5
# ============================================================
echo ""
echo "=== Test 9: SIG-CRASH-CLUSTER NOT triggered when agent has <=5 traces ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # Only 5 total traces for "general-purpose", all crashed — but count is exactly 5,
    # threshold requires > 5 so should NOT trigger
    {
        for i in 1 2 3 4 5; do
            make_entry "general-purpose" "crashed" "main" "general-purpose" 30 0
        done
        make_entry "implementer" "success" "feature/a" "implementer" 120 5
    } > "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-CRASH-CLUSTER") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ -z "$SIG" ]]; then
        pass "SIG-CRASH-CLUSTER correctly absent when count=5 (threshold >5)"
    else
        fail "SIG-CRASH-CLUSTER incorrectly triggered when count=5 (threshold requires >5)"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 10: SIG-PROOF-UNKNOWN NOT triggered when <80% unknown
# ============================================================
echo ""
echo "=== Test 10: SIG-PROOF-UNKNOWN NOT triggered when <80% manifests unknown ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # 3 verified, 1 unknown = 25% unknown — below 80% threshold
    for i in 1 2 3; do
        trace_dir="${trace_store}/trace-ok-00${i}"
        mkdir -p "${trace_dir}/artifacts"
        printf '{"proof_status":"verified","session_id":"ok-%s"}\n' "$i" > "${trace_dir}/manifest.json"
    done
    trace_dir="${trace_store}/trace-unknown-001"
    mkdir -p "${trace_dir}/artifacts"
    printf '{"proof_status":"unknown","session_id":"unknown-1"}\n' > "${trace_dir}/manifest.json"

    make_entry "implementer" "success" "feature/ok" "implementer" 120 5 > "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    SIG=$(jq -r '.improvement_signals[] | select(.id == "SIG-PROOF-UNKNOWN") | .id' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "")
    if [[ -z "$SIG" ]]; then
        pass "SIG-PROOF-UNKNOWN correctly absent when only 25% unknown (below 80% threshold)"
    else
        fail "SIG-PROOF-UNKNOWN incorrectly triggered when only 25% unknown"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 11: suggest.sh processes new signals — metadata present for all 7
# ============================================================
echo ""
echo "=== Test 11: suggest.sh has metadata for all 7 new signal IDs ==="
{
    tmp=$(setup_env)
    obs_dir="${tmp}/observatory"
    suggestions_dir="${obs_dir}/suggestions"
    mkdir -p "$suggestions_dir"

    # Write an analysis-cache with all 7 new signals
    cat > "${obs_dir}/analysis-cache.json" << 'CACHE_EOF'
{
  "version": 2,
  "generated_at": "2026-02-17T00:00:00Z",
  "trace_stats": {"total": 100},
  "artifact_health": {"total_traces": 10, "completeness": {}},
  "self_metrics": {"total_suggestions": 0, "implemented": 0, "rejected": 0, "acceptance_rate": null},
  "improvement_signals": [
    {"id": "SIG-MAIN-IMPL", "category": "workflow_compliance", "severity": "high", "description": "Implementer on main", "evidence": {"affected_count": 3, "total": 100}, "root_cause": "No worktree"},
    {"id": "SIG-BRANCH-UNKNOWN", "category": "workflow_compliance", "severity": "low", "description": "Branch unknown", "evidence": {"affected_count": 5, "total": 100}, "root_cause": "git fail"},
    {"id": "SIG-AGENT-TYPE-MISMATCH", "category": "workflow_compliance", "severity": "medium", "description": "Plan vs planner", "evidence": {"affected_count": 2, "total": 100}, "root_cause": "No normalization"},
    {"id": "SIG-CRASH-CLUSTER", "category": "agent_performance", "severity": "high", "description": "Crash cluster", "evidence": {"affected_count": 1, "total": 100, "crash_cluster_agents": []}, "root_cause": "Prompt bug"},
    {"id": "SIG-STALE-MARKERS", "category": "agent_performance", "severity": "low", "description": "Stale markers", "evidence": {"affected_count": 2, "total": 100, "stale_markers": []}, "root_cause": "No cleanup"},
    {"id": "SIG-PROOF-UNKNOWN", "category": "trace_infrastructure", "severity": "medium", "description": "Proof unknown", "evidence": {"affected_count": 45, "total": 50}, "root_cause": "No scope"}
  ],
  "trends": null,
  "agent_breakdown": []
}
CACHE_EOF

    # Clean state so nothing is skipped
    cat > "${obs_dir}/state.json" << 'STATE_EOF'
{"version":2,"last_analysis_at":null,"last_analysis_trace_count":0,"pending_suggestion":null,"pending_title":null,"pending_priority":null,"implemented":[],"rejected":[],"deferred":[]}
STATE_EOF

    OBS_DIR="$obs_dir" STATE_FILE="${obs_dir}/state.json" \
        bash "$SUGGEST_SCRIPT" > /dev/null 2>&1

    # Verify all 7 signals produced suggestions
    NEW_SIGS=("SIG-MAIN-IMPL" "SIG-BRANCH-UNKNOWN" "SIG-AGENT-TYPE-MISMATCH" "SIG-CRASH-CLUSTER" "SIG-STALE-MARKERS" "SIG-PROOF-UNKNOWN")
    ALL_FOUND=true
    for sig in "${NEW_SIGS[@]}"; do
        FOUND=$(jq -r --arg id "$sig" 'select(.signal_id == $id) | .id' "${suggestions_dir}"/SUG-*.json 2>/dev/null | head -1 || echo "")
        if [[ -n "$FOUND" ]]; then
            pass "suggest.sh has metadata for $sig → generated $FOUND"
        else
            fail "suggest.sh missing metadata for $sig — no suggestion generated"
            ALL_FOUND=false
        fi
    done
    rm -rf "$tmp"
}

# ============================================================
# TEST 12: New fields in trace_stats (main_impl_count, branch_unknown_count, agent_type_plan_count)
# ============================================================
echo ""
echo "=== Test 12: New trace_stats fields present in analysis-cache.json ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    make_entry "implementer" "success" "main" "implementer" 120 5 > "${trace_store}/index.jsonl"
    make_entry "planner" "success" "unknown" "Plan" 60 0 >> "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    MAIN_IMPL=$(jq '.trace_stats.main_impl_count // "MISSING"' "${obs_dir}/analysis-cache.json")
    BRANCH_UNK=$(jq '.trace_stats.branch_unknown_count // "MISSING"' "${obs_dir}/analysis-cache.json")
    PLAN_TYPE=$(jq '.trace_stats.agent_type_plan_count // "MISSING"' "${obs_dir}/analysis-cache.json")

    if [[ "$MAIN_IMPL" != '"MISSING"' ]] && [[ "$BRANCH_UNK" != '"MISSING"' ]] && [[ "$PLAN_TYPE" != '"MISSING"' ]]; then
        pass "trace_stats has main_impl_count=$MAIN_IMPL, branch_unknown_count=$BRANCH_UNK, agent_type_plan_count=$PLAN_TYPE"
    else
        fail "trace_stats missing new fields: main_impl_count=$MAIN_IMPL branch_unknown_count=$BRANCH_UNK agent_type_plan_count=$PLAN_TYPE"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 13: stale_markers top-level field in analysis-cache.json
# ============================================================
echo ""
echo "=== Test 13: stale_markers top-level field present in analysis-cache.json ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    make_entry "implementer" "success" "feature/a" "implementer" 120 5 > "${trace_store}/index.jsonl"
    touch "${trace_store}/.active-orphan-marker"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    STALE=$(jq '.stale_markers // "MISSING"' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo '"MISSING"')
    if [[ "$STALE" != '"MISSING"' ]]; then
        COUNT=$(jq '.stale_markers.count' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo "MISSING")
        pass "stale_markers field present (count=$COUNT)"
    else
        fail "stale_markers top-level field missing from analysis-cache.json"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 14: proof_unknown_count in artifact_health
# ============================================================
echo ""
echo "=== Test 14: proof_unknown_count in artifact_health ==="
{
    tmp=$(setup_env)
    trace_store="${tmp}/traces"
    obs_dir="${tmp}/observatory"

    # 2 trace dirs with unknown proof_status
    for i in 1 2; do
        trace_dir="${trace_store}/trace-pu-00${i}"
        mkdir -p "${trace_dir}/artifacts"
        printf '{"proof_status":"unknown"}\n' > "${trace_dir}/manifest.json"
    done

    make_entry "implementer" "success" "feature/a" "implementer" 120 5 > "${trace_store}/index.jsonl"

    CLAUDE_DIR="$tmp" OBS_DIR="$obs_dir" TRACE_INDEX="${trace_store}/index.jsonl" \
        TRACE_STORE="$trace_store" WORKTREE_DIR="$tmp" STATE_FILE="${obs_dir}/state.json" \
        bash "$ANALYZE_SCRIPT" > /dev/null 2>&1

    PU_COUNT=$(jq '.artifact_health.proof_unknown_count // "MISSING"' "${obs_dir}/analysis-cache.json" 2>/dev/null || echo '"MISSING"')
    if [[ "$PU_COUNT" != '"MISSING"' ]]; then
        pass "artifact_health.proof_unknown_count present (=$PU_COUNT)"
    else
        fail "artifact_health.proof_unknown_count missing from analysis-cache.json"
    fi
    rm -rf "$tmp"
}

# ============================================================
# TEST 15: category_weight for new categories in suggest.sh
# ============================================================
echo ""
echo "=== Test 15: New category weights in suggest.sh (workflow_compliance, agent_performance, trace_infrastructure) ==="
{
    tmp=$(setup_env)
    obs_dir="${tmp}/observatory"
    suggestions_dir="${obs_dir}/suggestions"
    mkdir -p "$suggestions_dir"

    # One signal per new category — verify they get suggestions (weight > 0)
    cat > "${obs_dir}/analysis-cache.json" << 'CACHE_EOF'
{
  "version": 2,
  "generated_at": "2026-02-17T00:00:00Z",
  "trace_stats": {"total": 50},
  "artifact_health": {"total_traces": 5, "completeness": {}},
  "self_metrics": {"total_suggestions": 0, "implemented": 0, "rejected": 0, "acceptance_rate": null},
  "improvement_signals": [
    {"id": "SIG-MAIN-IMPL", "category": "workflow_compliance", "severity": "high", "description": "test", "evidence": {"affected_count": 5, "total": 50}, "root_cause": "test"},
    {"id": "SIG-STALE-MARKERS", "category": "agent_performance", "severity": "low", "description": "test", "evidence": {"affected_count": 2, "total": 50, "stale_markers": []}, "root_cause": "test"},
    {"id": "SIG-PROOF-UNKNOWN", "category": "trace_infrastructure", "severity": "medium", "description": "test", "evidence": {"affected_count": 40, "total": 50}, "root_cause": "test"}
  ],
  "trends": null,
  "agent_breakdown": []
}
CACHE_EOF

    cat > "${obs_dir}/state.json" << 'STATE_EOF'
{"version":2,"last_analysis_at":null,"last_analysis_trace_count":0,"pending_suggestion":null,"pending_title":null,"pending_priority":null,"implemented":[],"rejected":[],"deferred":[]}
STATE_EOF

    OBS_DIR="$obs_dir" STATE_FILE="${obs_dir}/state.json" \
        bash "$SUGGEST_SCRIPT" > /dev/null 2>&1

    SUG_COUNT=$(ls "${suggestions_dir}"/SUG-*.json 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$SUG_COUNT" -eq 3 ]]; then
        # Check priority scores are > 0 (non-zero weights)
        MIN_SCORE=$(jq -r '.priority_score' "${suggestions_dir}"/SUG-*.json | sort -n | head -1)
        ABOVE_ZERO=$(jq -n "$MIN_SCORE > 0" 2>/dev/null || echo "false")
        if [[ "$ABOVE_ZERO" == "true" ]]; then
            pass "All 3 new-category signals got suggestions with non-zero priority"
        else
            fail "At least one signal has zero priority (weight broken): min=$MIN_SCORE"
        fi
    else
        fail "Expected 3 suggestions for 3 new-category signals, got $SUG_COUNT"
    fi
    rm -rf "$tmp"
}

# ============================================================
# Summary
# ============================================================
echo ""
echo "====================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "====================================="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
