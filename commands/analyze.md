---
name: analyze
description: Bootstrap a session with full repo knowledgebase context for deep analysis
---

# /analyze — Repo Analysis Session Bootstrap

Load the knowledgebase for a git repository and prepare for deep analysis work.

## Arguments

`$ARGUMENTS` — Optional repo path. Defaults to the current working directory.

## Workflow

### Step 1: Resolve the target repo

```
REPO_PATH = $ARGUMENTS or current working directory
```

Validate that `REPO_PATH` is a git repository (contains `.git/`). If not, tell the user and stop.

### Step 2: Check for existing analysis kit

Look for `<REPO_PATH>/analysis/CLAUDE.md`. If it exists, the repo has been indexed before.

**If analysis kit exists:**
1. Read `<REPO_PATH>/analysis/CLAUDE.md` — this is the architecture overview
2. Read `<REPO_PATH>/analysis/patterns.md` — pattern catalog
3. Read `<REPO_PATH>/analysis/decisions.md` — decision history
4. List files in `<REPO_PATH>/analysis/rules/` and `<REPO_PATH>/analysis/knowledge/`
5. Summarize what's available and ask the user what they want to analyze

**If analysis kit does NOT exist:**
1. Tell the user: "No analysis kit found for this repo. Run `/generate-knowledge <path>` first to build one."
2. Offer to run it now: "Would you like me to generate the knowledgebase now?"
3. If yes, invoke the `/generate-knowledge` skill with the repo path

### Step 3: Trigger MCP indexing if available

Check if the `claude-context` MCP server is available (try calling `index_codebase` tool). If available:
- Call `index_codebase` with the repo path to ensure semantic search is up to date
- Call `get_indexing_status` to show progress

Check if the `code-graph-rag` MCP server is available (try calling `index_repository` tool). If available:
- Call `index_repository` with the repo path to ensure the knowledge graph is current

If MCP servers are not available, proceed with Layer 1 only and note this to the user.

### Step 4: Present the analysis session

Summarize what's loaded and available:

```
Repo Knowledgebase: <repo-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Layer 1 (Knowledge Files): ✓ Loaded
  - Architecture overview
  - N component rules
  - N subsystem knowledge files
  - Pattern catalog
  - Decision history

Layer 2 (Semantic Search): ✓ Available / ✗ Not configured
Layer 3 (Knowledge Graph): ✓ Available / ✗ Not configured

Ready for analysis. What would you like to explore?
```

### Step 5: Maintain context throughout the session

During the analysis session:
- Reference the analysis kit files when answering questions
- Use semantic search (Layer 2) for finding relevant code
- Use the knowledge graph (Layer 3) for structural queries (call chains, dependencies)
- When you learn something new about the repo, suggest updating the analysis kit

## Tips for the user

- "What does the authentication system do?" → Layer 1 knowledge files + Layer 2 search
- "What calls the UserService.create method?" → Layer 3 graph query
- "Find all error handling patterns" → Layer 2 semantic search + Layer 1 patterns
- "How has the API changed over time?" → Layer 1 decisions + git log analysis
