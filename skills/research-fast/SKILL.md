---
name: research-fast
description: Speed-focused research using Gemini Deep Research Agent for autonomous multi-step synthesis (1-2 min). Use when you need quick expert synthesis, exploratory research, learning workflows, strategic planning with actionable frameworks, or trust Gemini's autonomous judgment. Output is expert synthesis style in markdown format. Best for: competitive analysis, trend analysis, quick overviews.
argument-hint: "[research topic or question]"
context: fork
agent: general-purpose
---

# research-fast: Gemini Deep Research Agent Integration

Harness Google's Gemini Deep Research capabilities for autonomous, multi-step research workflows.

## What This Does

This skill invokes the Gemini CLI's deep research agent to:
- Autonomously plan and execute multi-step research
- Search across multiple sources
- Synthesize findings into comprehensive reports
- Provide structured, citation-backed analysis

## When to Use This

**Use research-fast when:**
- You need exploratory research with autonomous planning
- You want Gemini's unique research approach and synthesis
- You're researching recent developments or trends
- You need comparative analysis across domains
- You want to leverage Gemini's multi-source aggregation

**Don't use this when:**
- You need simple lookups (use WebSearch instead)
- You're debugging code (use standard tools)
- You need the 8-phase enterprise pipeline (use /research-verified instead)
- You need credibility scoring (use /research-verified instead)

## How It Works

1. **Parse Query**: Understand what you're researching
2. **Invoke Gemini CLI**: Call Gemini's deep research agent
3. **Wait for Completion**: Research runs autonomously
4. **Synthesize Results**: Format and present findings
5. **Deliver Report**: Markdown + summary in Claude Code

## Setup (First Time Only)

The skill requires a Gemini API key. If not configured, you'll be prompted to set it up:

```bash
mkdir -p ~/.config/research-fast
cat > ~/.config/research-fast/.env << 'EOF'
# Gemini Research Configuration
GEMINI_API_KEY=your_api_key_here
EOF

chmod 600 ~/.config/research-fast/.env
```

Get your API key from: https://aistudio.google.com/apikey

## Usage Examples

### Exploratory Research
```
/research-fast latest developments in AI coding assistants
```

### Comparative Analysis
```
/research-fast compare Claude Code vs GitHub Copilot vs Cursor
```

### Trend Analysis
```
/research-fast AI agent frameworks trends 2026
```

### Domain-Specific Research
```
/research-fast quantum computing commercial applications
```

## Output Format

Results are saved to:
- **Markdown**: `~/Documents/GeminiResearch_[Topic]_[Date]/research_[date]_[topic].md`
- **Chat summary**: Key findings displayed inline

Each report includes:
- Research question and scope
- Key findings and insights
- Source references
- Synthesis and recommendations
- Methodology notes

## Comparison: research-fast vs research-verified

| Feature | research-fast | research-verified |
|---------|----------------|---------------|
| **Engine** | Gemini Deep Research | 8-phase custom pipeline |
| **Planning** | Autonomous | Structured phases |
| **Credibility Scoring** | No | Yes (0-100 scale) |
| **Citation Format** | Gemini-style | Academic [N] format |
| **Speed** | Variable (Gemini-dependent) | Predictable by mode |
| **Best For** | Exploratory, autonomous | Structured, enterprise |
| **Output Formats** | Markdown | Markdown + HTML + PDF |

## Research Quality

Gemini Deep Research provides:
- Multi-source aggregation
- Autonomous query refinement
- Progressive exploration
- Natural language synthesis

For maximum research coverage, consider using BOTH skills:
1. `/research-fast` for autonomous exploration
2. `/research-verified` for structured verification

## Technical Notes

- **CLI Version**: Requires Gemini CLI v0.26.0+
- **API**: Uses Gemini API for deep research mode
- **Timeout**: No hard timeout; research runs until complete
- **Caching**: Results cached per session

## Workflow Integration

This skill works well with:
- `/research-verified` - For complementary structured analysis
- `/last30days` - For recent social discussions
- WebSearch - For quick fact-checking during synthesis

## Configuration

Location: `~/.config/research-fast/.env`

Required variables:
- `GEMINI_API_KEY` - Your Gemini API key

Optional variables:
- `GEMINI_TIMEOUT` - Custom timeout in seconds (default: no limit)
- `OUTPUT_DIR` - Custom output directory (default: ~/Documents)

## Error Handling

The skill handles:
- Missing API key → Prompt for configuration
- CLI not found → Installation instructions
- API errors → Graceful degradation with error details
- Timeout issues → Partial results if available

## Privacy & Data

- Research queries sent to Gemini API
- API key stored locally in ~/.config/
- Results saved to local filesystem only
- No data sent to third parties (except Gemini API)

---

**Note**: This skill is a wrapper around the Gemini CLI deep research feature. Results quality depends on Gemini's research agent capabilities.
