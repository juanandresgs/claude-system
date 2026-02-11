#!/usr/bin/env python3
"""report.py — Generate human-readable Markdown report from uplevel JSON.

@decision Markdown output with Unicode bar charts for visual scoring.
Separate from score.py because scoring is pure computation while
reporting is presentation — different change cadences.

Usage:
    python3 report.py --input <uplevel_report.json> --output <uplevel_report.md>
"""

import argparse
import json
import sys
from pathlib import Path

SEVERITY_EMOJI = {
    "critical": "CRITICAL",
    "high": "HIGH",
    "medium": "MEDIUM",
    "low": "LOW",
    "info": "INFO",
}

AREA_DISPLAY = {
    "security": "Security",
    "testing": "Testing & Coverage",
    "quality": "Code Quality & Health",
    "documentation": "Documentation",
    "staleness": "Staleness & Maintenance",
    "standards": "Standards & Professionalism",
}


def score_bar(score: int, width: int = 10) -> str:
    """Render a Unicode bar chart for a score out of 100."""
    filled = round(score / 100 * width)
    empty = width - filled
    return "\u2588" * filled + "\u2591" * empty


def rating_for_score(score: float) -> str:
    """Map score to rating label."""
    if score >= 90:
        return "Exemplary"
    elif score >= 70:
        return "Healthy"
    elif score >= 50:
        return "Needs Work"
    elif score >= 30:
        return "At Risk"
    else:
        return "Critical"


def generate_report(data: dict) -> str:
    """Generate full Markdown report from unified JSON."""
    lines = []

    # Header
    project_name = data.get("project", {}).get("remote", "") or data.get("project", {}).get("root", "unknown")
    # Extract just repo name from URL
    if "/" in project_name:
        project_name = "/".join(project_name.rstrip("/").split("/")[-2:])

    timestamp = data.get("timestamp", "unknown")[:10]
    overall = data.get("overall_score", 0)
    rating = data.get("rating", rating_for_score(overall))

    lines.append(f"# Repository Health Report: {project_name}")
    lines.append(f"**Date:** {timestamp} | **Overall Score: {overall}/100** | **Rating: {rating}**")
    lines.append("")

    # Score Summary Table
    lines.append("## Score Summary")
    lines.append("")
    lines.append("| Area | Score | Rating |")
    lines.append("|------|-------|--------|")

    areas = data.get("areas", {})
    area_order = ["security", "testing", "quality", "documentation", "staleness", "standards"]
    for area in area_order:
        if area not in areas:
            continue
        area_data = areas[area]
        score = area_data.get("score", 0)
        bar = score_bar(score)
        area_rating = area_data.get("rating", rating_for_score(score))
        display_name = AREA_DISPLAY.get(area, area.title())
        error_note = " (audit failed)" if "error" in area_data else ""
        lines.append(f"| {display_name} | {score}/100 | {bar} {area_rating}{error_note} |")

    lines.append("")

    # Top Critical Findings
    all_findings = data.get("all_findings", [])
    critical_high = [f for f in all_findings if f.get("severity", "").lower() in ("critical", "high")]

    if critical_high:
        lines.append("## Top Findings (Critical & High)")
        lines.append("")
        for i, finding in enumerate(critical_high[:10], 1):
            sev = SEVERITY_EMOJI.get(finding.get("severity", "").lower(), "?")
            fid = finding.get("id", "???")
            title = finding.get("title", "Unknown finding")
            lines.append(f"{i}. **[{sev}]** `{fid}`: {title}")
        lines.append("")

    # Per-Area Details
    lines.append("## Area Details")
    lines.append("")

    for area in area_order:
        if area not in areas:
            continue
        area_data = areas[area]
        score = area_data.get("score", 0)
        display_name = AREA_DISPLAY.get(area, area.title())
        lines.append(f"### {display_name} ({score}/100)")
        lines.append("")

        if "error" in area_data:
            lines.append(f"> Audit failed: {area_data['error']}")
            lines.append("")
            continue

        findings = area_data.get("findings", [])
        if not findings:
            lines.append("No findings — area is clean.")
            lines.append("")
            continue

        lines.append("| ID | Severity | Title | Effort |")
        lines.append("|----|----------|-------|--------|")
        for f in findings:
            fid = f.get("id", "???")
            sev = f.get("severity", "info").upper()
            title = f.get("title", "Unknown")
            effort = f.get("effort", "?")
            lines.append(f"| `{fid}` | {sev} | {title} | {effort} |")
        lines.append("")

        # Show remediation details for critical/high findings
        important = [f for f in findings if f.get("severity", "").lower() in ("critical", "high")]
        if important:
            lines.append("**Details for critical/high findings:**")
            lines.append("")
            for f in important:
                fid = f.get("id", "???")
                lines.append(f"**`{fid}`: {f.get('title', '')}**")
                if f.get("description"):
                    lines.append(f"- **What:** {f['description']}")
                if f.get("impact"):
                    lines.append(f"- **Impact:** {f['impact']}")
                if f.get("remediation"):
                    lines.append(f"- **Fix:** {f['remediation']}")
                lines.append("")

    # Remediation Plan
    lines.append("## Remediation Plan")
    lines.append("")

    immediate = [f for f in all_findings if f.get("severity", "").lower() in ("critical", "high")]
    short_term = [f for f in all_findings if f.get("severity", "").lower() == "medium"]
    backlog = [f for f in all_findings if f.get("severity", "").lower() in ("low", "info")]

    if immediate:
        lines.append("### Immediate (Critical/High)")
        lines.append("")
        for f in immediate:
            fid = f.get("id", "???")
            title = f.get("title", "Unknown")
            remediation = f.get("remediation", "See finding details")
            lines.append(f"- [ ] `{fid}`: {title} — {remediation}")
        lines.append("")

    if short_term:
        lines.append("### Short-term (Medium)")
        lines.append("")
        for f in short_term:
            fid = f.get("id", "???")
            title = f.get("title", "Unknown")
            lines.append(f"- [ ] `{fid}`: {title}")
        lines.append("")

    if backlog:
        lines.append("### Backlog (Low/Info)")
        lines.append("")
        for f in backlog:
            fid = f.get("id", "???")
            title = f.get("title", "Unknown")
            lines.append(f"- [ ] `{fid}`: {title}")
        lines.append("")

    # Summary stats
    summary = data.get("summary", {})
    total = sum(summary.values())
    lines.append("---")
    lines.append(f"*Total findings: {total} ({summary.get('critical', 0)} critical, "
                 f"{summary.get('high', 0)} high, {summary.get('medium', 0)} medium, "
                 f"{summary.get('low', 0)} low, {summary.get('info', 0)} info)*")
    lines.append("")
    lines.append("*Generated by `/uplevel` — repository health audit*")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Uplevel Markdown report generator")
    parser.add_argument("--input", required=True, help="Path to uplevel_report.json")
    parser.add_argument("--output", required=True, help="Path to write uplevel_report.md")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    with open(input_path) as f:
        data = json.load(f)

    report_md = generate_report(data)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        f.write(report_md)

    print(f"Markdown report written to: {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
