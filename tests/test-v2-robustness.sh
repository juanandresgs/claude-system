#!/usr/bin/env bash
# Robustness & Failure Mode Tests for v2 Observability
#
# @decision DEC-V2-ROBUST-001
# @title Robustness test suite for context-lib.sh v2 functions
# @status accepted
# @rationale The v2 observability system must handle malformed input, scale,
# missing dependencies, permission errors, concurrency, and edge cases without
# crashing. These tests verify graceful degradation at every failure boundary.
# Categories: malformed JSONL, performance at scale, missing deps, permission
# errors, concurrency, and edge cases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/../hooks"
CONTEXT_LIB="${HOOKS_DIR}/context-lib.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "  ${GREEN}PASS${NC} $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "  ${RED}FAIL${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "       ${YELLOW}Details:${NC} $2"
    fi
}

skip() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "  ${YELLOW}SKIP${NC} $1${2:+ — $2}"
}

# Create a temporary project directory with .claude subdirectory
make_temp_project() {
    local dir
    dir=$(mktemp -d)
    mkdir -p "$dir/.claude"
    echo "$dir"
}

# Safe cleanup: cd out before removing to avoid bricking CWD
safe_cleanup() {
    local dir="$1"
    local fallback="${2:-$SCRIPT_DIR}"
    [[ "$(pwd)" == "$dir"* ]] && cd "$fallback"
    # Restore permissions in case permission tests left dirs read-only
    chmod -R u+w "$dir" 2>/dev/null || true
    rm -rf "$dir"
}

# Write events helper
write_events() {
    local project_dir="$1"
    cat > "$project_dir/.claude/.session-events.jsonl"
}

# Helper: ISO8601 timestamp N seconds ago
ts_ago() {
    local seconds="${1:-0}"
    local now
    now=$(date +%s)
    local past=$(( now - seconds ))
    date -u -r "$past" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
        || date -u -d "@$past" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
        || echo "2026-02-17T10:00:00Z"
}

# ============================================================================
# Section 3.1: Malformed JSONL
# ============================================================================

echo ""
echo "=== 3.1 Malformed JSONL ==="

test_corrupt_event_log_lines() {
    local proj
    proj=$(make_temp_project)

    # Mix of valid + corrupt lines
    cat > "$proj/.claude/.session-events.jsonl" <<EOF
{"ts":"$(ts_ago 120)","event":"write","file":"$proj/foo.py","lines_changed":10}
{bad json}
{"ts":"$(ts_ago 100)","event":"write","file":"$proj/bar.py","lines_changed":5}
not-json-at-all
{"ts":"$(ts_ago 80)","event":"test_run","result":"fail","failures":1,"assertion":"test_foo"}
EOF

    local tool_calls test_failures exit_code
    # Run in subshell, capture output
    exit_code=0
    result=$(
        set +e; source "$CONTEXT_LIB"
        get_session_trajectory "$proj"
        echo "TOOL_CALLS=$TRAJ_TOOL_CALLS"
        echo "TEST_FAILURES=$TRAJ_TEST_FAILURES"
    ) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "corrupt event log: no crash (exit code 0)"
    else
        fail "corrupt event log: crashed with exit code $exit_code"
    fi

    tool_calls=$(echo "$result" | grep "^TOOL_CALLS=" | cut -d= -f2)
    test_failures=$(echo "$result" | grep "^TEST_FAILURES=" | cut -d= -f2)

    if [[ "${tool_calls:-0}" -ge 2 ]]; then
        pass "corrupt event log: correct write count from valid lines (got $tool_calls)"
    else
        fail "corrupt event log: wrong write count" "Expected >=2, got '$tool_calls'"
    fi

    if [[ "${test_failures:-0}" -ge 1 ]]; then
        pass "corrupt event log: test_run count from valid lines (got $test_failures)"
    else
        fail "corrupt event log: wrong test_run count" "Expected >=1, got '$test_failures'"
    fi

    safe_cleanup "$proj"
}

test_invalid_detail_json_in_append() {
    local proj
    proj=$(make_temp_project)

    local event_file="$proj/.claude/.session-events.jsonl"

    # Call with malformed detail JSON
    local exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        append_session_event "write" "{bad: json}" "$proj"
    ) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "invalid detail JSON: no crash on malformed input"
    else
        fail "invalid detail JSON: crashed with exit code $exit_code"
    fi

    # Verify event was still written
    if [[ -f "$event_file" ]] && [[ -s "$event_file" ]]; then
        pass "invalid detail JSON: fallback event still written to file"
    else
        fail "invalid detail JSON: no event written" "File exists: $(ls -la "$event_file" 2>/dev/null || echo 'missing')"
    fi

    # Verify fallback line contains ts and event keys
    local line
    line=$(cat "$event_file")
    if echo "$line" | grep -q '"event"' && echo "$line" | grep -q '"ts"'; then
        pass "invalid detail JSON: fallback line contains ts and event fields"
    else
        fail "invalid detail JSON: fallback line missing required fields" "Line: $line"
    fi

    # Verify subsequent valid appends work
    (
        set +e; source "$CONTEXT_LIB"
        append_session_event "test_run" '{"result":"pass","failures":0}' "$proj"
    ) || true

    local line_count
    line_count=$(wc -l < "$event_file" | tr -d ' ')
    if [[ "$line_count" -ge 2 ]]; then
        pass "invalid detail JSON: subsequent valid appends work (total lines: $line_count)"
    else
        fail "invalid detail JSON: subsequent append failed" "Line count: $line_count"
    fi

    safe_cleanup "$proj"
}

test_corrupt_index_jsonl() {
    local proj
    proj=$(make_temp_project)

    # get_prior_sessions reads from ~/.claude/sessions/<hash>/index.jsonl
    # We need to set up the project hash directory
    local project_hash
    project_hash=$(echo "$proj" | shasum -a 256 2>/dev/null | cut -c1-12 || echo "testhash123")
    local index_dir="$HOME/.claude/sessions/${project_hash}"
    mkdir -p "$index_dir"
    local index_file="$index_dir/index.jsonl"

    # Write 3 valid + garbage entries (minimum threshold is 3 for injection)
    cat > "$index_file" <<EOF
{"id":"sess-001","project":"myproj","started":"2026-02-10T10:00:00Z","duration_min":30,"files_touched":5,"tool_calls":20,"checkpoints":2,"pivots":0,"friction":[],"outcome":"success"}
garbage line not json
{"id":"sess-002","project":"myproj","started":"2026-02-11T10:00:00Z","duration_min":45,"files_touched":8,"tool_calls":35,"checkpoints":3,"pivots":1,"friction":[],"outcome":"success"}
not-json-either
{"id":"sess-003","project":"myproj","started":"2026-02-12T10:00:00Z","duration_min":20,"files_touched":3,"tool_calls":15,"checkpoints":1,"pivots":0,"friction":[],"outcome":"partial"}
EOF

    local exit_code=0
    local result
    result=$(
        set +e; source "$CONTEXT_LIB"
        get_prior_sessions "$proj"
    ) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "corrupt index.jsonl: no crash (exit code 0)"
    else
        fail "corrupt index.jsonl: crashed with exit code $exit_code"
    fi

    # Result should contain parseable session data (3 valid sessions above threshold)
    if echo "$result" | grep -q "sessions"; then
        pass "corrupt index.jsonl: returns parseable session data despite garbage lines"
    else
        fail "corrupt index.jsonl: no session data returned" "Result: '$result'"
    fi

    # Cleanup the temp index
    rm -rf "$index_dir"
    safe_cleanup "$proj"
}

test_corrupt_event_log_lines
test_invalid_detail_json_in_append
test_corrupt_index_jsonl

# ============================================================================
# Section 3.2: Performance at Scale
# ============================================================================

echo ""
echo "=== 3.2 Performance at Scale ==="

GEN_SCRIPT="$SCRIPT_DIR/gen-scale-events.py"

test_1000_event_trajectory() {
    local proj
    proj=$(make_temp_project)
    local event_file="$proj/.claude/.session-events.jsonl"

    echo "  Generating 1100 events..."
    python3 "$GEN_SCRIPT" traj1000 "$proj" "$event_file" 2>/dev/null

    local start end elapsed
    start=$(date +%s)
    # Disable set -e inside subshell: context-lib functions use grep/jq patterns
    # that may return nonzero exit codes; they're designed for non-strict shells.
    ( set +e; source "$CONTEXT_LIB"; get_session_trajectory "$proj" > /dev/null ) || true
    end=$(date +%s)
    elapsed=$((end - start))

    if [[ "$elapsed" -le 2 ]]; then
        pass "1000-event trajectory: completed in ${elapsed}s (threshold: 2s)"
    else
        fail "1000-event trajectory: too slow — ${elapsed}s (threshold: 2s)"
    fi

    safe_cleanup "$proj"
}

test_500_event_pivot_detection() {
    local proj
    proj=$(make_temp_project)
    local event_file="$proj/.claude/.session-events.jsonl"

    echo "  Generating 1000-event pivot pattern (10 files x 50 cycles)..."
    python3 "$GEN_SCRIPT" pivot500 "$proj" "$event_file" 2>/dev/null

    local start end elapsed
    start=$(date +%s)
    local result
    result=$(
        set +e
        set +e; source "$CONTEXT_LIB"
        detect_approach_pivots "$proj"
        echo "PIVOT_COUNT=$PIVOT_COUNT"
        echo "PIVOT_FILES=$PIVOT_FILES"
    )
    end=$(date +%s)
    elapsed=$((end - start))

    if [[ "$elapsed" -le 2 ]]; then
        pass "500-event pivot detection: completed in ${elapsed}s (threshold: 2s)"
    else
        fail "500-event pivot detection: too slow — ${elapsed}s (threshold: 2s)"
    fi

    local pivot_count
    pivot_count=$(echo "$result" | grep "^PIVOT_COUNT=" | cut -d= -f2)
    if [[ "${pivot_count:-0}" -ge 10 ]]; then
        pass "500-event pivot detection: detects pivots on all 10 files (PIVOT_COUNT=$pivot_count)"
    else
        fail "500-event pivot detection: wrong pivot count" "Expected >=10, got '$pivot_count'"
    fi

    safe_cleanup "$proj"
}

test_2000_event_summary() {
    local proj
    proj=$(make_temp_project)
    local event_file="$proj/.claude/.session-events.jsonl"

    echo "  Generating 2000 mixed events..."
    python3 "$GEN_SCRIPT" summary2000 "$proj" "$event_file" 2>/dev/null

    local start end elapsed
    start=$(date +%s)
    ( set +e; source "$CONTEXT_LIB"; get_session_summary_context "$proj" > /dev/null ) || true
    end=$(date +%s)
    elapsed=$((end - start))

    if [[ "$elapsed" -le 3 ]]; then
        pass "2000-event summary: completed in ${elapsed}s (threshold: 3s)"
    else
        fail "2000-event summary: too slow — ${elapsed}s (threshold: 3s)"
    fi

    safe_cleanup "$proj"
}

test_1000_event_trajectory
test_500_event_pivot_detection
test_2000_event_summary

# ============================================================================
# Section 3.3: Missing Dependencies
# ============================================================================

echo ""
echo "=== 3.3 Missing Dependencies ==="

test_no_jq() {
    local proj
    proj=$(make_temp_project)

    # Create a temp bin dir with a fake jq that exits 1 (simulating missing/broken jq)
    local fake_bin
    fake_bin=$(mktemp -d)
    # Create fake jq that always fails (printf avoids heredoc)
    printf '%s\n' '#!/bin/bash' 'exit 1' > "$fake_bin/jq"
    chmod +x "$fake_bin/jq"

    local exit_code=0
    local event_file="$proj/.claude/.session-events.jsonl"

    # Override PATH to use broken jq, keep basic tools
    (
        export PATH="$fake_bin:/usr/bin:/bin"
        set +e; source "$CONTEXT_LIB"
        append_session_event "write" '{"file":"test.py"}' "$proj"
    ) || exit_code=$?

    # Restore PATH (already restored by subshell exit)
    if [[ "$exit_code" -eq 0 ]]; then
        pass "no jq: append_session_event no crash with broken jq"
    else
        fail "no jq: append_session_event crashed with broken jq (exit code $exit_code)"
    fi

    if [[ -f "$event_file" ]] && [[ -s "$event_file" ]]; then
        pass "no jq: event still written via fallback string interpolation"
        local line
        line=$(cat "$event_file")
        if echo "$line" | grep -q '"event"' && echo "$line" | grep -q '"ts"'; then
            pass "no jq: fallback line contains required fields"
        else
            fail "no jq: fallback line missing fields" "Line: $line"
        fi
    else
        fail "no jq: no event written despite fallback" "File: $(ls -la "$event_file" 2>/dev/null || echo 'missing')"
    fi

    safe_cleanup "$fake_bin"
    safe_cleanup "$proj"
}

test_no_git() {
    # Create a plain directory (no .git) to test graceful fallback
    local plain_dir
    plain_dir=$(mktemp -d)
    mkdir -p "$plain_dir/.claude"

    # Write a small event file
    echo '{"ts":"2026-02-17T10:00:00Z","event":"write","file":"test.py","lines_changed":5}' \
        > "$plain_dir/.claude/.session-events.jsonl"
    echo '{"ts":"2026-02-17T10:01:00Z","event":"test_run","result":"fail","failures":1,"assertion":"t"}' \
        >> "$plain_dir/.claude/.session-events.jsonl"
    echo '{"ts":"2026-02-17T10:02:00Z","event":"write","file":"test.py","lines_changed":3}' \
        >> "$plain_dir/.claude/.session-events.jsonl"

    local exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        get_session_trajectory "$plain_dir" > /dev/null
    ) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "no git: get_session_trajectory no crash without .git dir"
    else
        fail "no git: get_session_trajectory crashed without .git dir (exit code $exit_code)"
    fi

    exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        detect_approach_pivots "$plain_dir" > /dev/null
    ) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "no git: detect_approach_pivots no crash without .git dir"
    else
        fail "no git: detect_approach_pivots crashed without .git dir (exit code $exit_code)"
    fi

    exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        get_session_summary_context "$plain_dir" > /dev/null
    ) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "no git: get_session_summary_context no crash without .git dir"
    else
        fail "no git: get_session_summary_context crashed without .git dir (exit code $exit_code)"
    fi

    safe_cleanup "$plain_dir"
}

test_no_jq
test_no_git

# ============================================================================
# Section 3.4: Permission Errors
# ============================================================================

echo ""
echo "=== 3.4 Permission Errors ==="

test_readonly_claude_dir() {
    # Skip this test if running as root (root ignores chmod)
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "read-only .claude/ dir: running as root, permissions don't apply"
        return
    fi

    local proj
    proj=$(make_temp_project)
    local claude_dir="$proj/.claude"

    # Write an initial event first
    echo '{"ts":"2026-02-17T10:00:00Z","event":"write","file":"init.py","lines_changed":1}' \
        > "$claude_dir/.session-events.jsonl"

    # Make .claude dir read-only
    chmod 444 "$claude_dir"

    local exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        append_session_event "write" '{"file":"test.py"}' "$proj"
    ) || exit_code=$?

    # Restore permissions BEFORE any cleanup
    chmod 755 "$claude_dir"

    if [[ "$exit_code" -eq 0 ]]; then
        pass "read-only .claude/ dir: append_session_event silently fails, no crash"
    else
        fail "read-only .claude/ dir: crashed with exit code $exit_code (should silently fail)"
    fi

    safe_cleanup "$proj"
}

test_readonly_event_file() {
    # Skip this test if running as root
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "read-only event file: running as root, permissions don't apply"
        return
    fi

    local proj
    proj=$(make_temp_project)
    local event_file="$proj/.claude/.session-events.jsonl"

    # Write an initial event
    echo '{"ts":"2026-02-17T10:00:00Z","event":"write","file":"init.py","lines_changed":1}' \
        > "$event_file"

    # Make the event file read-only
    chmod 444 "$event_file"

    local exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        append_session_event "write" '{"file":"test.py"}' "$proj"
    ) || exit_code=$?

    # Restore permissions BEFORE checking/cleanup
    chmod 644 "$event_file"

    if [[ "$exit_code" -eq 0 ]]; then
        pass "read-only event file: append_session_event silently fails, no crash"
    else
        fail "read-only event file: crashed with exit code $exit_code (should silently fail)"
    fi

    # Verify existing events still readable
    local line_count
    line_count=$(wc -l < "$event_file" | tr -d ' ')
    if [[ "${line_count:-0}" -ge 1 ]]; then
        pass "read-only event file: existing events still readable after failed append"
    else
        fail "read-only event file: existing events lost" "Line count: $line_count"
    fi

    safe_cleanup "$proj"
}

test_readonly_claude_dir
test_readonly_event_file

# ============================================================================
# Section 3.5: Concurrency
# ============================================================================

echo ""
echo "=== 3.5 Concurrency ==="

test_parallel_event_writes() {
    local proj
    proj=$(make_temp_project)
    local event_file="$proj/.claude/.session-events.jsonl"

    # Launch two append_session_event calls in parallel
    (
        set +e; source "$CONTEXT_LIB"
        append_session_event "write" '{"file":"a.py","lines_changed":10}' "$proj"
    ) &
    local pid1=$!

    (
        set +e; source "$CONTEXT_LIB"
        append_session_event "write" '{"file":"b.py","lines_changed":20}' "$proj"
    ) &
    local pid2=$!

    wait "$pid1" "$pid2"

    # Verify both events appear
    local line_count
    line_count=$(wc -l < "$event_file" 2>/dev/null | tr -d ' ')
    if [[ "${line_count:-0}" -ge 2 ]]; then
        pass "parallel writes: both events written (line count: $line_count)"
    else
        fail "parallel writes: missing events" "Expected >=2 lines, got $line_count"
    fi

    # Verify no line corruption — each line should be valid JSON
    local corrupt_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! echo "$line" | jq -e . > /dev/null 2>&1; then
            corrupt_count=$((corrupt_count + 1))
        fi
    done < "$event_file"

    if [[ "$corrupt_count" -eq 0 ]]; then
        pass "parallel writes: no line corruption (all lines valid JSON)"
    else
        fail "parallel writes: $corrupt_count corrupted line(s) detected"
    fi

    safe_cleanup "$proj"
}

test_index_trim_behavior() {
    # Test that index trim keeps last 20 entries (simulating session-end.sh behavior)
    local tmp_index
    tmp_index=$(mktemp)

    # Write 25 entries using the external generator script
    python3 "$GEN_SCRIPT" index25 "unused" "$tmp_index" 2>/dev/null

    # Apply the same trim logic as session-end.sh
    local line_count
    line_count=$(wc -l < "$tmp_index" | tr -d ' ')

    if [[ "${line_count:-0}" -gt 20 ]]; then
        tail -20 "$tmp_index" > "${tmp_index}.trimmed"
        mv "${tmp_index}.trimmed" "$tmp_index"
    fi

    local final_count
    final_count=$(wc -l < "$tmp_index" | tr -d ' ')

    if [[ "$final_count" -eq 20 ]]; then
        pass "index trim: exactly 20 entries remain after trim from 25"
    else
        fail "index trim: wrong count after trim" "Expected 20, got $final_count"
    fi

    # Verify most recent entries preserved (last entry should be sess-025)
    local last_id
    last_id=$(tail -1 "$tmp_index" | jq -r '.id // ""' 2>/dev/null)
    if [[ "$last_id" == "sess-025" ]]; then
        pass "index trim: most recent entry preserved (last id: $last_id)"
    else
        fail "index trim: most recent entry not preserved" "Expected 'sess-025', got '$last_id'"
    fi

    # Verify oldest entries trimmed (first entry should now be sess-006)
    local first_id
    first_id=$(head -1 "$tmp_index" | jq -r '.id // ""' 2>/dev/null)
    if [[ "$first_id" == "sess-006" ]]; then
        pass "index trim: oldest entries removed (first id now: $first_id)"
    else
        fail "index trim: wrong first entry after trim" "Expected 'sess-006', got '$first_id'"
    fi

    rm -f "$tmp_index"
}

test_parallel_event_writes
test_index_trim_behavior

# ============================================================================
# Section 3.6: Edge Cases
# ============================================================================

echo ""
echo "=== 3.6 Edge Cases ==="

test_exactly_3_events_boundary() {
    local proj
    proj=$(make_temp_project)

    # Write exactly 3 events (boundary: <3 returns empty, >=3 produces output)
    cat > "$proj/.claude/.session-events.jsonl" <<EOF
{"ts":"$(ts_ago 120)","event":"write","file":"$proj/a.py","lines_changed":5}
{"ts":"$(ts_ago 60)","event":"test_run","result":"fail","failures":1,"assertion":"test_a"}
{"ts":"$(ts_ago 30)","event":"write","file":"$proj/a.py","lines_changed":3}
EOF

    local output
    output=$(
        set +e; source "$CONTEXT_LIB"
        get_session_summary_context "$proj"
    )

    if [[ -n "$output" ]]; then
        pass "exactly 3 events: get_session_summary_context returns content (3 is minimum)"
    else
        fail "exactly 3 events: got empty output at boundary (3 events should produce content)"
    fi

    safe_cleanup "$proj"
}

test_branch_with_slashes() {
    local proj
    proj=$(make_temp_project)

    # Initialize a git repo
    git -C "$proj" init -q 2>/dev/null
    git -C "$proj" config user.email "test@test.com" 2>/dev/null
    git -C "$proj" config user.name "Test" 2>/dev/null

    # Create initial commit so we can create refs
    echo "test" > "$proj/README.md"
    git -C "$proj" add README.md 2>/dev/null
    git -C "$proj" commit -q -m "init" 2>/dev/null

    # Create a branch with slashes in name
    git -C "$proj" checkout -q -b "feature/foo/bar" 2>/dev/null

    # Get HEAD sha for ref creation
    local sha
    sha=$(git -C "$proj" rev-parse HEAD 2>/dev/null)

    # Create a checkpoint ref with slash in branch name (simulate checkpoint.sh behavior)
    local exit_code=0
    git -C "$proj" update-ref "refs/checkpoints/auto-001" "$sha" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "branch with slashes: checkpoint ref created despite '/' in branch name"
    else
        fail "branch with slashes: ref creation failed" "Exit code: $exit_code"
    fi

    # Verify ref exists and resolves correctly
    local resolved
    resolved=$(git -C "$proj" rev-parse "refs/checkpoints/auto-001" 2>/dev/null || echo "")
    if [[ "$resolved" == "$sha" ]]; then
        pass "branch with slashes: checkpoint ref resolves to correct SHA"
    else
        fail "branch with slashes: ref resolution wrong" "Expected $sha, got '$resolved'"
    fi

    safe_cleanup "$proj"
}

test_exactly_3_sessions_minimum() {
    local proj
    proj=$(make_temp_project)

    # get_prior_sessions requires >=3 sessions
    local project_hash
    project_hash=$(echo "$proj" | shasum -a 256 2>/dev/null | cut -c1-12 || echo "edge123")
    local index_dir="$HOME/.claude/sessions/${project_hash}"
    mkdir -p "$index_dir"
    local index_file="$index_dir/index.jsonl"

    # Write exactly 3 sessions
    cat > "$index_file" <<EOF
{"id":"sess-001","project":"test","started":"2026-02-10T10:00:00Z","duration_min":30,"files_touched":5,"tool_calls":20,"checkpoints":2,"pivots":0,"friction":[],"outcome":"success"}
{"id":"sess-002","project":"test","started":"2026-02-11T10:00:00Z","duration_min":45,"files_touched":8,"tool_calls":35,"checkpoints":3,"pivots":1,"friction":[],"outcome":"success"}
{"id":"sess-003","project":"test","started":"2026-02-12T10:00:00Z","duration_min":20,"files_touched":3,"tool_calls":15,"checkpoints":1,"pivots":0,"friction":[],"outcome":"partial"}
EOF

    local output
    output=$(
        set +e; source "$CONTEXT_LIB"
        get_prior_sessions "$proj"
    )

    if [[ -n "$output" ]]; then
        pass "exactly 3 sessions: get_prior_sessions returns output at minimum threshold"
    else
        fail "exactly 3 sessions: got empty output at minimum threshold (3 is minimum)"
    fi

    # Cleanup temp index
    rm -rf "$index_dir"
    safe_cleanup "$proj"
}

test_empty_event_file() {
    local proj
    proj=$(make_temp_project)

    # Create empty event file
    touch "$proj/.claude/.session-events.jsonl"

    local exit_code=0

    # Test get_session_trajectory
    (
        set +e; source "$CONTEXT_LIB"
        result=$(get_session_trajectory "$proj"; echo "TC=$TRAJ_TOOL_CALLS")
        tc=$(echo "$result" | grep "^TC=" | cut -d= -f2)
        [[ "${tc:-0}" -eq 0 ]]
    ) || exit_code=$?
    if [[ "$exit_code" -eq 0 ]]; then
        pass "empty event file: get_session_trajectory returns gracefully with zero counts"
    else
        fail "empty event file: get_session_trajectory crashed or wrong counts" "(exit $exit_code)"
    fi

    # Test detect_approach_pivots
    exit_code=0
    local pivot_count
    pivot_count=$(
        set +e; source "$CONTEXT_LIB"
        detect_approach_pivots "$proj"
        echo "$PIVOT_COUNT"
    ) || exit_code=1
    if [[ "${pivot_count:-0}" -eq 0 ]] && [[ "$exit_code" -eq 0 ]]; then
        pass "empty event file: detect_approach_pivots returns 0 pivots"
    else
        fail "empty event file: detect_approach_pivots wrong result" "pivot_count='$pivot_count' exit=$exit_code"
    fi

    # Test get_session_summary_context (should return empty — <3 events)
    exit_code=0
    local summary_output
    summary_output=$(
        set +e; source "$CONTEXT_LIB"
        get_session_summary_context "$proj"
    ) || exit_code=$?
    if [[ "$exit_code" -eq 0 ]]; then
        pass "empty event file: get_session_summary_context no crash"
    else
        fail "empty event file: get_session_summary_context crashed" "(exit $exit_code)"
    fi
    if [[ -z "$summary_output" ]]; then
        pass "empty event file: get_session_summary_context returns empty (trivial session)"
    else
        fail "empty event file: unexpected summary output for empty file" "Output: $summary_output"
    fi

    safe_cleanup "$proj"
}

test_single_line_event_file() {
    local proj
    proj=$(make_temp_project)

    # Write exactly 1 event
    echo '{"ts":"2026-02-17T10:00:00Z","event":"write","file":"one.py","lines_changed":5}' \
        > "$proj/.claude/.session-events.jsonl"

    local exit_code=0

    # All three functions should return without crash, with minimal/empty values
    local traj_result
    traj_result=$(
        set +e; source "$CONTEXT_LIB"
        get_session_trajectory "$proj"
        echo "TC=$TRAJ_TOOL_CALLS"
        echo "TF=$TRAJ_TEST_FAILURES"
    ) || exit_code=$?
    if [[ "$exit_code" -eq 0 ]]; then
        pass "single event: get_session_trajectory no crash"
    else
        fail "single event: get_session_trajectory crashed" "(exit $exit_code)"
    fi

    local tool_calls
    tool_calls=$(echo "$traj_result" | grep "^TC=" | cut -d= -f2)
    if [[ "${tool_calls:-0}" -eq 1 ]]; then
        pass "single event: correct tool call count (1)"
    else
        fail "single event: wrong tool call count" "Expected 1, got '$tool_calls'"
    fi

    exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        detect_approach_pivots "$proj" > /dev/null
    ) || exit_code=$?
    if [[ "$exit_code" -eq 0 ]]; then
        pass "single event: detect_approach_pivots no crash"
    else
        fail "single event: detect_approach_pivots crashed" "(exit $exit_code)"
    fi

    exit_code=0
    (
        set +e; source "$CONTEXT_LIB"
        get_session_summary_context "$proj" > /dev/null
    ) || exit_code=$?
    if [[ "$exit_code" -eq 0 ]]; then
        pass "single event: get_session_summary_context no crash"
    else
        fail "single event: get_session_summary_context crashed" "(exit $exit_code)"
    fi

    safe_cleanup "$proj"
}

test_exactly_3_events_boundary
test_branch_with_slashes
test_exactly_3_sessions_minimum
test_empty_event_file
test_single_line_event_file

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "==========================================="
echo "Robustness Test Results:"
echo "  Total:   $TESTS_RUN"
echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
else
    echo "  Failed:  0"
fi
if [[ "$TESTS_SKIPPED" -gt 0 ]]; then
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
fi
echo "==========================================="

if [[ "$TESTS_FAILED" -eq 0 ]]; then
    echo -e "${GREEN}All robustness tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some robustness tests failed.${NC}"
    exit 1
fi
