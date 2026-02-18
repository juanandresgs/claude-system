---
name: observatory
description: Self-improving system observatory — analyzes traces, suggests improvements, drives implementation.
argument-hint: "[run | report | status | history | analyze-only | backlog | batch <label>]"
context: fork
agent: general-purpose
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion
---

# /observatory — Self-Improving System Observatory

Analyzes trace data to surface data quality signals, ranks them by impact and feasibility, and proposes targeted improvements. Each accepted improvement is tracked in persistent state — forming a flywheel where the observatory improves its own analysis data over time.

## Modes

- `/observatory` or `/observatory run` — Full cycle: analyze → suggest → generate report → present report summary → approve/defer/reject → output work order
- `/observatory report` — Generate and present the full assessment report (all signals, comparison matrix, batches, backlog)
- `/observatory status` — Show current state (pending suggestion, acceptance rate, history)
- `/observatory history` — Show recent action log from history.jsonl
- `/observatory analyze-only` — Run analysis only, display findings without suggesting
- `/observatory backlog` — Show deferred items with reassessment status; allow re-evaluation
- `/observatory batch <label>` — Approve an entire batch of related signals as one work order

---

## Step 1: Parse Arguments

```bash
ARGS="${ARGUMENTS:-run}"
MODE="${ARGS%% *}"
BATCH_LABEL="${ARGS#* }"   # second word (for "batch A" → "A")
[[ -z "$MODE" || "$MODE" == "observatory" ]] && MODE="run"
```

Valid modes: `run`, `report`, `status`, `history`, `analyze-only`, `backlog`, `batch`. Default: `run`.

---

## Step 2: Handle status, history, and backlog modes (no analysis needed)

### status mode

```bash
STATE_FILE="$HOME/.claude/observatory/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
    echo "Observatory not yet initialized. Run /observatory to begin."
    exit 0
fi
cat "$STATE_FILE" | jq .
```

Present the state to the user: pending suggestion (if any), implemented count, rejected count, deferred count, acceptance rate.

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

### backlog mode

```bash
STATE_FILE="$HOME/.claude/observatory/state.json"
SUGGESTIONS_DIR="$HOME/.claude/observatory/suggestions"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "No state found. Run /observatory first."
    exit 0
fi

DEFERRED_COUNT=$(jq '.deferred | length' "$STATE_FILE")
if [[ "$DEFERRED_COUNT" -eq 0 ]]; then
    echo "No deferred items."
    exit 0
fi

NOW=$(date -u +%s)
```

Present each deferred item:
- Signal ID, when deferred, reason
- Reassessment date and condition
- Current priority vs. priority at deferral
- Whether it is now overdue for reassessment (reassess_after < now)

Then use AskUserQuestion to ask: for each deferred item, what action?
- **reassess** — re-evaluate priority against current data, move back to proposed pool
- **promote** — immediately move back to proposed pool
- **dismiss** — permanently reject (add to rejected list)
- **keep** — leave deferred, extend by 7 more days

For **reassess**: Re-run suggest.sh to get current priority. If priority has changed >10%, surface that delta.
For **promote**: `transition SUG_ID "proposed" title priority`
For **dismiss**: `transition SUG_ID "rejected" title priority`
For **keep**: Update `reassess_after` in state.json by +7 days.

---

## Step 3: Run Analysis (run, report, and analyze-only modes)

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

## Step 4: Generate Suggestions (run, report, batch modes)

```bash
bash "$HOME/.claude/skills/observatory/scripts/suggest.sh" 2>&1
```

If suggest.sh fails, report the error and stop.

---

## Step 5: Generate Assessment Report (run and report modes)

```bash
bash "$HOME/.claude/skills/observatory/scripts/report.sh" 2>&1
```

If report.sh fails, report the error and stop.

Read the generated report:

```bash
REPORT="$HOME/.claude/observatory/assessment-report.md"
cat "$REPORT"
```

Present the full report to the user. Then offer a decision menu.

---

## Step 6: Present Report and Decision Menu (run mode)

After presenting the report, ask the user using AskUserQuestion:

```
What would you like to do?

1. **Approve top suggestion** — Generate a work order for the highest-priority signal
2. **Approve batch** — Approve all signals in a batch as one work order (e.g., "approve batch A")
3. **Review a specific signal** — Show full detail on a specific SUG-NNN or signal
4. **Defer a suggestion** — Skip a signal with a reassessment date
5. **Reject a suggestion** — Permanently dismiss a signal
6. **Show backlog** — See deferred items and reassessment status
7. **Exit** — Do nothing
```

Parse the user's response:
- "approve top" / "approve 1" / "1" → approve the highest-priority proposed suggestion
- "approve batch A" / "batch A" / "batch a" → approve entire batch A (see Batch Approval below)
- "review SUG-001" / "SUG-001" → show full suggestion detail
- "defer SUG-001" / "defer 2" → defer that suggestion
- "reject SUG-001" / "reject 3" → reject that suggestion
- "backlog" / "6" → switch to backlog mode flow
- "exit" / "7" / empty → exit without action

---

## Step 7: Act on Decision

Source the state library:

```bash
source "$HOME/.claude/skills/observatory/scripts/state.sh"
```

### On approve (single suggestion)

Find the highest-priority proposed suggestion:

```bash
SUGGESTIONS_DIR="$HOME/.claude/observatory/suggestions"
TOP_SUG=$(ls "$SUGGESTIONS_DIR"/SUG-*.json 2>/dev/null | \
    xargs jq -r 'select(.status == "proposed") | "\(.priority_score) \(.id)"' 2>/dev/null | \
    sort -rn | head -1 | awk '{print $2}')
```

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

### Batch Approval Flow

When the user selects "approve batch LABEL":

```bash
MATRIX_FILE="$HOME/.claude/observatory/comparison-matrix.json"
BATCH_LABEL="A"  # from user input

# Get all signals in this batch
BATCH_SIGS=$(jq -r --arg b "$BATCH_LABEL" '.batches[$b].signals[]' "$MATRIX_FILE")
BATCH_FILES=$(jq -c --arg b "$BATCH_LABEL" '.batches[$b].files' "$MATRIX_FILE")
BATCH_EFFORT=$(jq -r --arg b "$BATCH_LABEL" '.batches[$b].combined_effort' "$MATRIX_FILE")
```

1. Transition each suggestion in the batch to accepted.

2. Write a single combined work order to `.skill-result.md`:

```markdown
## Observatory Batch Improvement: Batch [LABEL] — [batch label description]

**Batch:** [label] | **Signals:** [count] | **Effort:** [combined_effort]
**Shared Files:** [files list]

### Signals in This Batch

For each signal in the batch:
- **[SUG-ID] — [signal_id]**: [title]
  - Evidence: [impact.scope] ([severity])
  - Root cause: [root_cause from analysis-cache]
  - Priority: [priority_score]

### Implementation Plan

Implement all changes to [files list] as one coherent unit:

For each signal:
**[signal_id] change:**
[implementation.approach]

### Test Strategy

For each signal:
**[signal_id] test:**
[implementation.test_strategy]

Run all tests together: any regression means the batch partially failed.
```

3. Tell the user: "Batch work order written for [N] signals. The orchestrator will dispatch a single implementer run to apply all changes."

### On defer

```bash
source "$HOME/.claude/skills/observatory/scripts/state.sh"
defer_with_context "$SUG_ID" "$SIGNAL_ID" "user" 7 "re-evaluate after next observatory run" "$PRIORITY"
```

Tell the user: "[SUG-ID] deferred for 7 days. It will re-enter the proposed pool after [date]."

### On reject

```bash
transition "$SUG_ID" "rejected" "[title]" "[priority_score]"
```

Tell the user: "[SUG-ID] rejected. It will not be proposed again."

---

## report mode (standalone)

When mode is `report`:
1. Run Steps 3-5 (analyze → suggest → report)
2. Present the full report
3. Ask: "Would you like to act on any of these signals?" and proceed to Step 6 decision menu.

## batch mode (standalone)

When mode is `batch LABEL`:
1. Run Steps 3-5 (analyze → suggest → report)
2. Find the batch by label in comparison-matrix.json
3. Present the batch signals and combined implementation plan
4. Use AskUserQuestion: "Approve this batch? (yes/no)"
5. If yes: execute Batch Approval flow above
6. If no: exit without action

---

## Important Behaviors

- **Idempotent analysis:** Running `/observatory` twice is safe — analyze.sh overwrites analysis-cache.json, suggest.sh only creates new SUG files for unimplemented signals.
- **Persistence across sessions:** observatory/state.json and observatory/history.jsonl survive sessions. The pending_suggestion field allows resuming an interrupted approval flow.
- **Observatory self-improves:** The first suggestions fix the duration/test/files bugs in finalize_trace, which improves the data quality for all subsequent observatory runs.
- **Do not auto-approve:** Always use AskUserQuestion — the user must explicitly approve each improvement. The flywheel is human-in-the-loop by design.
- **Deferred items resurface automatically:** analyze.sh calls auto_resurface() at startup, which moves items past their reassess_after date back to the proposed pool.
- **Trend arrows:** The report shows whether the signal count is improving, worsening, or stable since the last run.
