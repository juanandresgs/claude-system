#!/usr/bin/env python3
"""score.py — Scoring engine for /uplevel repository health audit.

@decision Weighted scoring with configurable area weights. Security gets
highest weight (25%) because vulnerabilities are existential risk.
Testing (20%) and Code Quality (20%) follow because they gate daily
developer experience. Docs/Staleness/Standards are important but
lower-impact.

Usage:
    python3 score.py --areas-dir <dir> --output <path> [--project-info <json>]

Input:  Per-area JSON reports in areas-dir/{area}_report.json
Output: Unified uplevel_report.json with overall score and all findings.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Area weights — must sum to 1.0
AREA_WEIGHTS = {
    "security": 0.25,
    "testing": 0.20,
    "quality": 0.20,
    "documentation": 0.15,
    "staleness": 0.10,
    "standards": 0.10,
}

RATING_THRESHOLDS = [
    (90, "Exemplary"),
    (70, "Healthy"),
    (50, "Needs Work"),
    (30, "At Risk"),
    (0, "Critical"),
]


def get_rating(score: float) -> str:
    """Map numeric score to human-readable rating."""
    for threshold, label in RATING_THRESHOLDS:
        if score >= threshold:
            return label
    return "Critical"


def load_area_report(areas_dir: Path, area: str) -> dict:
    """Load a single area report, returning a default if missing/invalid."""
    report_path = areas_dir / f"{area}_report.json"
    if not report_path.exists():
        return {
            "area": area,
            "score": 0,
            "findings": [],
            "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
            "error": f"Area report not found: {report_path}",
        }
    try:
        with open(report_path) as f:
            data = json.load(f)
        # Validate required fields
        if "score" not in data:
            data["score"] = 0
        if "findings" not in data:
            data["findings"] = []
        if "summary" not in data:
            data["summary"] = compute_summary(data["findings"])
        data["area"] = area
        return data
    except (json.JSONDecodeError, OSError) as e:
        return {
            "area": area,
            "score": 0,
            "findings": [],
            "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
            "error": str(e),
        }


def compute_summary(findings: list) -> dict:
    """Count findings by severity level."""
    summary = {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0}
    for f in findings:
        sev = f.get("severity", "info").lower()
        if sev in summary:
            summary[sev] += 1
    return summary


def compute_overall_score(area_reports: dict) -> float:
    """Compute weighted overall score from area scores."""
    total = 0.0
    for area, weight in AREA_WEIGHTS.items():
        report = area_reports.get(area, {})
        score = report.get("score", 0)
        # Clamp to 0-100
        score = max(0, min(100, score))
        total += score * weight
    return round(total, 1)


def aggregate_findings(area_reports: dict) -> list:
    """Collect all findings across areas, sorted by severity."""
    severity_order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
    all_findings = []
    for area, report in area_reports.items():
        for finding in report.get("findings", []):
            finding["area"] = area
            all_findings.append(finding)
    all_findings.sort(key=lambda f: severity_order.get(f.get("severity", "info").lower(), 5))
    return all_findings


def aggregate_summary(area_reports: dict) -> dict:
    """Sum up severity counts across all areas."""
    total = {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0}
    for report in area_reports.values():
        summary = report.get("summary", {})
        for level in total:
            total[level] += summary.get(level, 0)
    return total


def build_unified_report(area_reports: dict, project_info: dict) -> dict:
    """Build the complete unified report JSON."""
    overall_score = compute_overall_score(area_reports)

    # Build areas section with scores and ratings
    areas = {}
    for area in AREA_WEIGHTS:
        report = area_reports.get(area, {})
        score = report.get("score", 0)
        areas[area] = {
            "score": score,
            "rating": get_rating(score),
            "findings": report.get("findings", []),
            "summary": report.get("summary", compute_summary(report.get("findings", []))),
        }
        if "error" in report:
            areas[area]["error"] = report["error"]

    return {
        "version": "1.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "project": {
            "root": project_info.get("repo_root", ""),
            "remote": project_info.get("git_remote", ""),
            "primary_language": project_info.get("primary_language", ""),
            "languages": project_info.get("languages", []),
            "frameworks": project_info.get("frameworks", []),
        },
        "detection": project_info,
        "overall_score": overall_score,
        "rating": get_rating(overall_score),
        "areas": areas,
        "all_findings": aggregate_findings(area_reports),
        "summary": aggregate_summary(area_reports),
    }


def main():
    parser = argparse.ArgumentParser(description="Uplevel scoring engine")
    parser.add_argument("--areas-dir", required=True, help="Directory containing area_report.json files")
    parser.add_argument("--output", required=True, help="Path to write unified uplevel_report.json")
    parser.add_argument("--project-info", default="{}", help="Project detection JSON string")
    args = parser.parse_args()

    areas_dir = Path(args.areas_dir)
    if not areas_dir.exists():
        print(f"Error: areas directory not found: {areas_dir}", file=sys.stderr)
        sys.exit(1)

    try:
        project_info = json.loads(args.project_info)
    except json.JSONDecodeError:
        # Try reading as file path
        try:
            with open(args.project_info) as f:
                project_info = json.load(f)
        except (OSError, json.JSONDecodeError):
            project_info = {}

    # Load all area reports
    area_reports = {}
    for area in AREA_WEIGHTS:
        area_reports[area] = load_area_report(areas_dir, area)

    # Build unified report
    report = build_unified_report(area_reports, project_info)

    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)

    # Print summary to stderr
    print(f"Overall Score: {report['overall_score']}/100 ({report['rating']})", file=sys.stderr)
    for area, data in report["areas"].items():
        status = f" [ERROR: {data['error']}]" if "error" in data else ""
        print(f"  {area}: {data['score']}/100{status}", file=sys.stderr)
    s = report["summary"]
    print(f"Findings: {s['critical']}C {s['high']}H {s['medium']}M {s['low']}L {s['info']}I", file=sys.stderr)
    print(f"Report written to: {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
