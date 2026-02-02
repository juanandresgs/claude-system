#!/usr/bin/env python3
"""
# @decision DEC-GEMINI-001: Gemini CLI Integration Strategy
# @title Direct CLI invocation via subprocess for Gemini Deep Research
# @status accepted
# @rationale Direct CLI invocation provides better control over async execution,
# output streaming, and error handling compared to using SDK. Allows capturing
# real-time progress and integrating with Claude Code workflow naturally.
#
# Gemini Deep Research Engine
#
# This script invokes the Gemini CLI's deep research capabilities and formats
# the output for Claude Code integration. It handles API key management,
# subprocess execution, progress tracking, and result formatting.
#
# Usage:
#   python gemini_research.py "research query" [--output-dir DIR]
#
# Dependencies: Python 3.8+, subprocess, os, json (all stdlib)
"""

import subprocess
import sys
import os
import json
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, Optional, Tuple

# Constants
CONFIG_DIR = Path.home() / ".config" / "gemini-research"
ENV_FILE = CONFIG_DIR / ".env"
GEMINI_CLI_PATH = "/opt/homebrew/bin/gemini"
DEFAULT_OUTPUT_DIR = Path.home() / "Documents"

def load_config() -> Dict[str, str]:
    """Load configuration from .env file."""
    config = {}

    if ENV_FILE.exists():
        with open(ENV_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()

    return config

def check_api_key() -> Tuple[bool, Optional[str]]:
    """Check if Gemini API key is configured."""
    config = load_config()
    api_key = config.get('GEMINI_API_KEY', '').strip()

    if api_key and api_key != 'your_api_key_here':
        return True, api_key

    # Also check environment variable
    env_key = os.environ.get('GEMINI_API_KEY', '').strip()
    if env_key:
        return True, env_key

    return False, None

def setup_instructions() -> str:
    """Return setup instructions for missing API key."""
    return f"""
⚠️  Gemini API key not configured

To use research-fast, set up your API key:

1. Get your API key from: https://aistudio.google.com/apikey

2. Create config file:
   mkdir -p {CONFIG_DIR}
   cat > {ENV_FILE} << 'EOF'
GEMINI_API_KEY=your_actual_api_key_here
EOF
   chmod 600 {ENV_FILE}

3. Run the skill again

Alternatively, set the environment variable:
   export GEMINI_API_KEY=your_actual_api_key_here
"""

def check_gemini_cli() -> Tuple[bool, str]:
    """Check if Gemini CLI is installed and get version."""
    try:
        result = subprocess.run(
            [GEMINI_CLI_PATH, '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            version = result.stdout.strip().split('\n')[0]
            return True, version
        else:
            return False, "CLI found but version check failed"

    except FileNotFoundError:
        return False, f"Gemini CLI not found at {GEMINI_CLI_PATH}"
    except Exception as e:
        return False, f"Error checking CLI: {str(e)}"

def create_output_directory(topic: str, output_base: Optional[Path] = None) -> Path:
    """Create organized output directory for research results."""
    if output_base is None:
        output_base = DEFAULT_OUTPUT_DIR

    # Clean topic for directory name
    topic_clean = "".join(c if c.isalnum() or c in (' ', '_') else '_' for c in topic)
    topic_clean = '_'.join(topic_clean.split())[:50]  # Limit length

    date_str = datetime.now().strftime("%Y%m%d")
    dir_name = f"GeminiResearch_{topic_clean}_{date_str}"

    output_dir = output_base / dir_name
    output_dir.mkdir(parents=True, exist_ok=True)

    return output_dir

def extract_topic_slug(query: str) -> str:
    """Extract clean topic slug from research query."""
    # Remove common words and clean
    stop_words = {'the', 'a', 'an', 'in', 'on', 'at', 'for', 'to', 'of', 'and', 'or'}
    words = query.lower().split()
    words = [w for w in words if w not in stop_words]

    # Take first 5 meaningful words
    slug = '_'.join(words[:5])
    # Clean non-alphanumeric
    slug = ''.join(c if c.isalnum() or c == '_' else '_' for c in slug)

    return slug[:50]

def run_gemini_research(query: str, api_key: str, output_dir: Path) -> Tuple[bool, str, str]:
    """
    Run Gemini deep research via CLI.

    Returns: (success, output_text, error_message)
    """
    print(f"🔬 Starting Gemini Deep Research...")
    print(f"📝 Query: {query}")
    print(f"📂 Output: {output_dir}")
    print(f"⏳ Research in progress (this may take several minutes)...\n")

    # Prepare environment with API key
    env = os.environ.copy()
    env['GEMINI_API_KEY'] = api_key

    # Build command for deep research
    # Craft a research-focused prompt
    research_prompt = f"""Conduct comprehensive deep research on the following topic and provide a detailed report with sources:

{query}

Please provide:
1. A thorough analysis with multiple perspectives
2. Key findings and insights
3. Relevant data and statistics
4. Citations and sources
5. Summary and conclusions

Format the response as a structured research report."""

    # Use -p flag for non-interactive prompt
    # Note: --yolo removed as it's disabled by admin settings
    cmd = [
        GEMINI_CLI_PATH,
        '-p', research_prompt,
        '--output-format', 'text'
    ]

    try:
        # Run with streaming output
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            bufsize=1,
            universal_newlines=True
        )

        output_lines = []
        error_lines = []

        # Stream output in real-time
        while True:
            output = process.stdout.readline()
            if output:
                line = output.strip()
                output_lines.append(line)
                # Show progress indicators
                if any(marker in line.lower() for marker in ['searching', 'analyzing', 'synthesizing', 'step']):
                    print(f"  {line}")

            # Check if process finished
            if output == '' and process.poll() is not None:
                break

        # Get any remaining output
        remaining_out, remaining_err = process.communicate()
        if remaining_out:
            output_lines.extend(remaining_out.strip().split('\n'))
        if remaining_err:
            error_lines.extend(remaining_err.strip().split('\n'))

        full_output = '\n'.join(output_lines)
        full_error = '\n'.join(error_lines)

        if process.returncode == 0:
            print("\n✅ Research completed successfully")
            return True, full_output, ""
        else:
            print(f"\n❌ Research failed with code {process.returncode}")
            return False, full_output, full_error

    except subprocess.TimeoutExpired:
        return False, "", "Research timed out"
    except Exception as e:
        return False, "", f"Error running research: {str(e)}"

def format_markdown_report(query: str, output: str, output_dir: Path) -> str:
    """Format Gemini output as structured markdown report."""
    date_str = datetime.now().strftime("%Y-%m-%d")
    topic_slug = extract_topic_slug(query)

    report = f"""# Gemini Deep Research Report

**Research Query:** {query}

**Date:** {date_str}

**Research Engine:** Gemini Deep Research Agent

---

## Research Output

{output}

---

## Methodology

This research was conducted using Google's Gemini Deep Research Agent, which:
- Autonomously plans multi-step research workflows
- Searches across multiple information sources
- Synthesizes findings into coherent narratives
- Provides citations and source references

## Notes

- Research conducted via Gemini CLI v0.26.0+
- Output generated autonomously by Gemini's research agent
- For complementary structured analysis, consider using /research-verified skill

---

*Generated by research-fast skill for Claude Code*
*Report saved to: {output_dir}*
"""

    return report

def save_report(report: str, output_dir: Path, topic_slug: str) -> Path:
    """Save markdown report to file."""
    date_str = datetime.now().strftime("%Y%m%d")
    filename = f"research_{date_str}_{topic_slug}.md"
    filepath = output_dir / filename

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(report)

    return filepath

def extract_summary(output: str, max_lines: int = 10) -> str:
    """Extract key findings summary from Gemini output."""
    lines = output.split('\n')

    # Try to find summary section
    summary_markers = ['summary', 'key findings', 'conclusion', 'highlights']
    summary_start = None

    for i, line in enumerate(lines):
        if any(marker in line.lower() for marker in summary_markers):
            summary_start = i
            break

    if summary_start is not None:
        # Take from summary marker onwards
        summary_lines = lines[summary_start:summary_start + max_lines]
        return '\n'.join(summary_lines)
    else:
        # Take first N lines as summary
        return '\n'.join(lines[:max_lines])

def main():
    """Main execution flow."""
    if len(sys.argv) < 2:
        print("Usage: python gemini_research.py \"research query\" [--output-dir DIR]")
        sys.exit(1)

    query = sys.argv[1]

    # Parse optional output directory
    output_base = None
    if '--output-dir' in sys.argv:
        idx = sys.argv.index('--output-dir')
        if idx + 1 < len(sys.argv):
            output_base = Path(sys.argv[idx + 1])

    # Step 1: Check API key
    has_key, api_key = check_api_key()
    if not has_key:
        print(setup_instructions())
        sys.exit(1)

    # Step 2: Check Gemini CLI
    cli_ok, cli_info = check_gemini_cli()
    if not cli_ok:
        print(f"❌ {cli_info}")
        print("\nInstall Gemini CLI: https://github.com/google/gemini-cli")
        sys.exit(1)

    print(f"✅ Gemini CLI detected: {cli_info}")

    # Step 3: Create output directory
    output_dir = create_output_directory(query, output_base)

    # Step 4: Run research
    success, output, error = run_gemini_research(query, api_key, output_dir)

    if not success:
        print(f"\n❌ Research failed")
        if error:
            print(f"Error: {error}")
        if output:
            print(f"Output: {output[:500]}")
        sys.exit(1)

    # Step 5: Format and save report
    topic_slug = extract_topic_slug(query)
    report = format_markdown_report(query, output, output_dir)
    filepath = save_report(report, output_dir, topic_slug)

    print(f"\n📄 Report saved: {filepath}")

    # Step 6: Output summary for Claude Code
    summary = extract_summary(output)

    print("\n" + "="*60)
    print("RESEARCH SUMMARY")
    print("="*60)
    print(summary)
    print("="*60)
    print(f"\n📂 Full report: {filepath}")
    print(f"📁 Research folder: {output_dir}")

    # Output structured result for Claude Code parsing
    result = {
        "success": True,
        "query": query,
        "report_path": str(filepath),
        "output_dir": str(output_dir),
        "summary": summary,
        "timestamp": datetime.now().isoformat()
    }

    print("\n[GEMINI_RESEARCH_RESULT]")
    print(json.dumps(result, indent=2))
    print("[/GEMINI_RESEARCH_RESULT]")

if __name__ == "__main__":
    main()
