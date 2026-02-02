# Gemini Research Skill for Claude Code

Autonomous multi-step research using Google's Gemini Deep Research Agent.

## Overview

This skill integrates the Gemini CLI's deep research capabilities into Claude Code, providing:

- **Autonomous Research**: Gemini plans and executes multi-step research workflows
- **Multi-Source Synthesis**: Aggregates information across various sources
- **Natural Language Output**: Results in readable, synthesized format
- **Local Storage**: All reports saved to organized directories

## Installation

The skill is installed at: `~/.claude/skills/research-fast/`

### Prerequisites

1. **Gemini CLI** (already installed at `/opt/homebrew/bin/gemini`)
   - Version: v0.26.0+
   - Verify: `gemini --version`

2. **Gemini API Key** (required)
   - Get from: https://aistudio.google.com/apikey
   - Configure at: `~/.config/research-fast/.env`

## Setup

First-time configuration:

```bash
# Create config directory
mkdir -p ~/.config/research-fast

# Create config file
cat > ~/.config/research-fast/.env << 'EOF'
GEMINI_API_KEY=your_actual_api_key_here
EOF

# Secure permissions
chmod 600 ~/.config/research-fast/.env
```

## Usage

### In Claude Code

Invoke via natural language:

```
Use research-fast to analyze AI coding assistant trends
```

Or explicitly:

```
/research-fast compare PostgreSQL vs Supabase
```

### Direct CLI Usage

```bash
python ~/.claude/skills/research-fast/scripts/gemini_research.py "your research query"
```

Optional arguments:
```bash
python gemini_research.py "query" --output-dir ~/custom/path
```

## What It Does

**Research Flow:**

1. **Parse Query** - Understand research intent
2. **Invoke Gemini** - Call Gemini Deep Research agent via CLI
3. **Monitor Progress** - Track research phases (searching, analyzing, synthesizing)
4. **Capture Output** - Collect all research findings
5. **Format Report** - Structure as markdown with metadata
6. **Save Results** - Write to organized directory
7. **Extract Summary** - Show key findings in chat
8. **Return Paths** - Provide file locations for review

## Output Structure

Reports saved to:
```
~/Documents/GeminiResearch_[Topic]_[Date]/
└── research_[date]_[topic].md
```

Each report includes:
- Research query
- Date and metadata
- Full Gemini research output
- Methodology notes
- File paths

## Example Queries

**Exploratory Research:**
```
/research-fast latest quantum computing breakthroughs
```

**Comparative Analysis:**
```
/research-fast React vs Vue vs Svelte 2026
```

**Trend Analysis:**
```
/research-fast AI agent framework adoption trends
```

**Domain Research:**
```
/research-fast longevity biotech funding landscape
```

## Comparison: research-fast vs research-verified

| Aspect | research-fast | research-verified |
|--------|----------------|---------------|
| **Research Engine** | Gemini Deep Research | Custom 8-phase pipeline |
| **Planning** | Autonomous (Gemini-led) | Structured phases |
| **Sources** | Gemini-aggregated | WebSearch + parallel agents |
| **Credibility** | Not scored | Scored 0-100 |
| **Citations** | Gemini-style | Academic [N] format |
| **Output Formats** | Markdown | Markdown + HTML + PDF |
| **Speed** | Variable | Predictable by mode |
| **Best For** | Exploration, autonomy | Structure, verification |
| **Length** | Gemini-determined | Configurable (Quick/Deep/Ultra) |

## When to Use Which Skill

**Use research-fast when:**
- You want autonomous research planning
- You trust Gemini's research methodology
- You need exploratory, open-ended research
- You want Gemini's unique synthesis approach

**Use research-verified when:**
- You need credibility scoring
- You want 8-phase structured pipeline
- You need HTML/PDF output formats
- You want explicit source verification
- You need custom research modes (Quick/Deep/Ultra)

**Use both when:**
- Maximum coverage is critical
- You want complementary perspectives
- You need verification across engines
- Budget allows (both use API calls)

## Technical Architecture

```
research-fast/
├── SKILL.md                       # Skill specification
├── README.md                      # This file
└── scripts/
    └── gemini_research.py         # Main research engine
```

**Key Decisions:**

- **DEC-GEMINI-001**: Direct CLI invocation via subprocess
  - Rationale: Better control over async execution and output streaming
  - Alternative considered: Gemini Python SDK (rejected for control reasons)

## Configuration Options

Located at: `~/.config/research-fast/.env`

**Required:**
```bash
GEMINI_API_KEY=your_key_here
```

**Optional:**
```bash
GEMINI_TIMEOUT=3600           # Custom timeout in seconds
OUTPUT_DIR=~/custom/path      # Custom output directory
```

## Error Handling

The skill handles:

1. **Missing API Key** → Setup instructions displayed
2. **CLI Not Found** → Installation guidance provided
3. **API Errors** → Error details + graceful exit
4. **Timeout** → Partial results if available
5. **Invalid Query** → Clear error message

## Privacy & Security

- API key stored locally in `~/.config/research-fast/.env`
- File permissions: 600 (user read/write only)
- Research queries sent to Gemini API (Google)
- Results stored locally only
- No third-party data sharing (except Gemini API)

## Troubleshooting

**"API key not configured":**
- Check `~/.config/research-fast/.env` exists
- Verify API key is valid (not placeholder)
- Try setting `export GEMINI_API_KEY=your_key`

**"Gemini CLI not found":**
- Verify installation: `which gemini`
- Check version: `gemini --version`
- Reinstall if needed

**"Research timed out":**
- Default: no timeout
- Set custom: `GEMINI_TIMEOUT=7200` in .env
- Complex queries may take longer

**"Empty output":**
- Check Gemini API status
- Verify API key has credits
- Try simpler query first

## Development

To modify the skill:

1. Edit `SKILL.md` for behavior changes
2. Edit `gemini_research.py` for logic changes
3. Test with: `python scripts/gemini_research.py "test query"`
4. Restart Claude Code to reload skill

## Version History

- **v1.0** (2026-02-01) - Initial release
  - Gemini CLI integration
  - Markdown report generation
  - Config management
  - Error handling

## Related Skills

- **/research-verified** - Enterprise 8-phase research pipeline
- **/last30days** - Recent social media research (Reddit/X)
- **WebSearch** - Quick web lookups

## License

User skill - modify as needed for your workflow

---

**Questions or issues?** Check:
- Gemini CLI docs: https://github.com/google/gemini-cli
- Gemini API docs: https://ai.google.dev/
- Claude Code skills guide: `~/.claude/README.md`
