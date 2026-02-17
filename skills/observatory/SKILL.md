---
name: observatory
description: Self-improving system observatory — analyzes traces, suggests improvements, drives implementation.
argument-hint: "[run | status | history | analyze-only]"
context: fork
agent: general-purpose
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion
---

# /observatory — Self-Improving System Observatory

Analyzes trace data to surface data quality signals, ranks them by impact and feasibility, and proposes targeted improvements. Each accepted improvement is tracked in persistent state — forming a flywheel where the observatory improves its own analysis data over time.

## Modes

- `/observatory` or `/observatory run` — Full cycle: analyze → suggest → present top suggestion → approve/defer/reject → output work order
- `/observatory status` — Show current state (pending suggestion, acceptance rate, history)
- `/observatory history` — Show recent action log from history.jsonl
- `/observatory analyze-only` — Run analysis only, display findings without suggesting

---

## Step 1: Parse Arguments

```bash
ARGS="${ARGUMENTS:-run}"
MODE="${ARGS%% *}"
[[ -z "$MODE" || "$MODE" == "observatory" ]] && MODE="run"
```

Valid modes: `run`, `status`, `history`, `analyze-only`. Default: `run`.

---

## Step 2: Handle status and history modes (no analysis needed)

### status mode

```bash
STATE_FILE="$HOME/.claude/observatory/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
    echo "Observatory not yet initialized. Run /observatory to begin."
    exit 0
fi
cat "$STATE_FILE" | jq .
```

Present the state to the user: pending suggestion (if any), implemented count, rejected count, acceptance rate.

### history mode

```bash
HISTORY_FILE="$HOME/.claude/observatory/history.jsonl"
if [[ ! -f "$HISTORY_FILE" ]]; then
    echo "No history yet. Run /observatory to begin."
    exit 0
fi
# Show last 20 entries, most recent first
tail -20 "$HISTORY_FILE" | jq -r '"[\(.ts)] \(.action)\(if .id then " \(.id)" else "" end)\(if .signals then " (\(.signals) signals)" else "" end)"' | tac
```

Present the history as a human-readable action log.

---

## Step 3: Run Analysis (run and analyze-only modes)

```bash
WORKTREE="$HOME/.claude"  # skills run from ~/.claude context
bash "$HOME/.claude/skills/observatory/scripts/analyze.sh" 2>&1
```

If analyze.sh fails, report the error and stop.

After analysis, read and present the findings:

```bash
CACHE="$HOME/.claude/observatory/analysis-cache.json"
TOTAL=$(jq '.trace_stats.total' "$CACHE")
SIG_COUNT=$(jq '.improvement_signals | length' "$CACHE")
FILES_ZERO_PCT=$(jq '.trace_stats.files_changed_zero_pct' "$CACHE")
UNKNOWN_TEST_PCT=$(jq -n "$(jq '.trace_stats.test_dist.unknown // 0' "$CACHE") / $TOTAL * 100 | round")
```

Present a concise summary to the user:
- Total traces analyzed
- Outcome distribution (partial/success/crashed breakdown)
- Test result unknown percentage
- Files-changed zero percentage
- Number of signals detected

### analyze-only mode: stop here

If mode is `analyze-only`, present the analysis findings and exit. Do NOT proceed to suggestion generation.

---

## Step 4: Generate Suggestions (run mode only)

```bash
bash "$HOME/.claude/skills/observatory/scripts/suggest.sh" 2>&1
```

If suggest.sh fails, report the error and stop.

---

## Step 5: Present Top Suggestion

Find the highest-priority proposed suggestion:

```bash
SUGGESTIONS_DIR="$HOME/.claude/observatory/suggestions"
TOP_SUG=$(ls "$SUGGESTIONS_DIR"/SUG-*.json 2>/dev/null | \
    xargs jq -r 'select(.status == "proposed") | "\(.priority_score) \(.id)"' 2>/dev/null | \
    sort -rn | head -1 | awk '{print $2}')

if [[ -z "$TOP_SUG" ]]; then
    echo "No pending suggestions. System is healthy or all suggestions have been addressed."
    exit 0
fi

SUG_DATA=$(cat "$SUGGESTIONS_DIR/${TOP_SUG}.json")
```

Present the suggestion with full context:

```
## Observatory Suggestion: [id] — [title]

**Signal:** [signal_id]
**Priority Score:** [priority_score] (scale 0–1)

### Problem
[description]

**Evidence:** [impact.scope] traces affected ([impact.severity] severity)

### Proposed Fix
**Files:** [implementation.files_to_modify joined with ", "]
**Approach:** [implementation.approach]
**Test Strategy:** [implementation.test_strategy]
```

---

## Step 6: Ask for User Decision

Use AskUserQuestion to get the user's decision:

```
Decision for [id]:
- **approve** — Accept this improvement and generate a work order for the implementer
- **defer** — Skip for now, propose again next run
- **reject** — Permanently dismiss this suggestion
```

Wait for the user's response. Accept any of: `approve`/`yes`/`accept`, `defer`/`skip`/`later`, `reject`/`no`/`dismiss`.

---

## Step 7: Act on Decision

Source the state library and transition the suggestion:

```bash
source "$HOME/.claude/skills/observatory/scripts/state.sh"
```

### On approve

1. Transition to accepted:
```bash
transition "$TOP_SUG" "accepted" "[title]" "[priority_score]"
```

2. Write a work order to `.skill-result.md`:

```markdown
## Observatory Improvement: [SUG-ID]

### Problem
[description from suggestion]

**Evidence:** [impact.scope] ([impact.severity] severity)
**Signal Root Cause:** [signal from analysis-cache improvement_signals[].root_cause]

### Files to Modify
[files_to_modify — one per line with full path from ~/.claude/]

### Approach
[implementation.approach — verbatim from suggestion]

### Test Strategy
[implementation.test_strategy — verbatim from suggestion]

### Priority Score
[priority_score] — generated by observatory on [generated_at from analysis-cache]
```

3. Tell the user: "Work order written. The orchestrator will dispatch the implementer to apply this fix."

### On defer

```bash
transition "$TOP_SUG" "deferred" "[title]" "[priority_score]"
```

Tell the user: "[SUG-ID] deferred. It will be re-proposed on the next observatory run."

### On reject

```bash
transition "$TOP_SUG" "rejected" "[title]" "[priority_score]"
```

Tell the user: "[SUG-ID] rejected. It will not be proposed again."

---

## Important Behaviors

- **Idempotent analysis:** Running `/observatory` twice is safe — analyze.sh overwrites analysis-cache.json, suggest.sh only creates new SUG files for unimplemented signals.
- **Persistence across sessions:** observatory/state.json and observatory/history.jsonl survive sessions. The pending_suggestion field allows resuming an interrupted approval flow.
- **Observatory self-improves:** The first suggestions fix the duration/test/files bugs in finalize_trace, which improves the data quality for all subsequent observatory runs.
- **Do not auto-approve:** Always use AskUserQuestion — the user must explicitly approve each improvement. The flywheel is human-in-the-loop by design.
