---
name: generate-knowledge
description: Analyze any git repo and generate a structured knowledge kit for persistent context
argument-hint: "[/path/to/repo]"
---

# generate-knowledge: Repo Analysis Kit Generator

Fully automated analysis of any git repository. Produces a structured analysis kit of markdown files that serve as persistent, compaction-surviving context for Claude Code sessions.

## Usage

- `/generate-knowledge` — analyze the current working directory
- `/generate-knowledge /path/to/repo` — analyze a specific repo

## Execution Steps

### Step 1: Determine Repo Path

```
REPO_PATH = $ARGUMENTS or current working directory
```

Resolve to an absolute path. Validate it's a git repository (contains `.git/`). If not, tell the user and stop.

### Step 2: Run the Generation Engine

Execute the Python generation engine:

```bash
python3 /Users/turla/Code/repo-knowledgebase/scripts/generate_knowledge.py --repo-path "$REPO_PATH"
```

To write to a custom output directory:

```bash
python3 /Users/turla/Code/repo-knowledgebase/scripts/generate_knowledge.py --repo-path "$REPO_PATH" --output-dir /custom/output
```

### Step 3: Present Results

After the script completes:

1. Read `<REPO_PATH>/analysis/CLAUDE.md` to extract project name and tech stack
2. List all generated files with brief descriptions
3. Report any warnings from the generation engine

Present a summary like:

```
Analysis Kit Generated: <project-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  analysis/CLAUDE.md          Architecture overview
  analysis/patterns.md        N patterns detected
  analysis/decisions.md       N decisions extracted
  analysis/rules/             N component rule files
  analysis/knowledge/         N subsystem knowledge files

Next: Use /analyze to start a session with full context.
```

### Step 4: Suggest Next Steps

- Run `/analyze` to bootstrap a session with the knowledge
- Review and refine `analysis/CLAUDE.md` for accuracy
- Add the `analysis/` directory to version control for persistence

## Error Handling

- If the Python script exits non-zero, display its stderr output
- If the repo has no commits, inform the user
- If Python 3.10+ is not available, tell the user to install it

## Output Structure

```
<repo>/analysis/
  CLAUDE.md          — Architecture overview, tech stack, entry points
  patterns.md        — Naming, import, error handling, testing patterns
  decisions.md       — @decision annotations and git log decisions
  rules/
    <component>.md   — Per-directory component rules and API
  knowledge/
    <subsystem>.md   — Deep-dive subsystem knowledge files
```

## Dependencies

- Python 3.10+ (stdlib only — no pip install required)
- git CLI
- Optional: gh CLI (for PR-based decision extraction)
