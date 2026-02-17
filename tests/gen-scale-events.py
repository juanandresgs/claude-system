#!/usr/bin/env python3
"""
Generate scale test event files for test-v2-robustness.sh.

@decision DEC-V2-ROBUST-002
@title Python event generator for scale tests instead of bash loops
@status accepted
@rationale Bash loops with >> append (one syscall per iteration) are ~50x slower
than writing from Python with a single open file handle. For 1000-2000 event
files, bash loops take 30+ seconds; Python takes under 1 second. This helper
is invoked by the robustness test suite for scale test setup only.

Usage:
  gen-scale-events.py <mode> <proj> <event_file>

Modes:
  traj1000      — 1000 write + 100 test_run events
  pivot500      — 10 files x 50 write/fail cycles (1000 events)
  summary2000   — 800 write + 400 test_run + 100 checkpoint + 700 agent_start
  index25       — 25 index.jsonl entries for trim test
"""

import sys
import json


def main():
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[1]
    proj = sys.argv[2]
    out_file = sys.argv[3]
    ts = "2026-02-17T10:00:00Z"

    with open(out_file, 'w') as f:
        if mode == "traj1000":
            for i in range(1, 1001):
                f.write(json.dumps({
                    "ts": ts, "event": "write",
                    "file": f"{proj}/file_{i % 20}.py",
                    "lines_changed": i % 50 + 1
                }) + "\n")
            for i in range(1, 101):
                f.write(json.dumps({
                    "ts": ts, "event": "test_run", "result": "fail",
                    "failures": 1, "assertion": f"test_{i % 10}"
                }) + "\n")

        elif mode == "pivot500":
            for file_idx in range(1, 11):
                for cycle in range(50):
                    f.write(json.dumps({
                        "ts": ts, "event": "write",
                        "file": f"{proj}/src/module_{file_idx}.py",
                        "lines_changed": 5
                    }) + "\n")
                    f.write(json.dumps({
                        "ts": ts, "event": "test_run", "result": "fail",
                        "failures": 1, "assertion": f"test_module_{file_idx}"
                    }) + "\n")

        elif mode == "summary2000":
            for i in range(1, 801):
                f.write(json.dumps({
                    "ts": ts, "event": "write",
                    "file": f"{proj}/file_{i % 40}.py",
                    "lines_changed": i % 100 + 1
                }) + "\n")
            for i in range(1, 401):
                result = "pass" if i % 3 == 0 else "fail"
                f.write(json.dumps({
                    "ts": ts, "event": "test_run", "result": result,
                    "failures": 0 if result == "pass" else 1,
                    "assertion": f"test_{i % 20}"
                }) + "\n")
            for i in range(1, 101):
                f.write(json.dumps({
                    "ts": ts, "event": "checkpoint",
                    "ref": f"auto-{i}"
                }) + "\n")
            for i in range(1, 701):
                f.write(json.dumps({
                    "ts": ts, "event": "agent_start",
                    "type": "implementer"
                }) + "\n")

        elif mode == "index25":
            for i in range(1, 26):
                day = (i % 28) + 1
                f.write(json.dumps({
                    "id": f"sess-{i:03d}",
                    "project": "test",
                    "started": f"2026-02-{day:02d}T10:00:00Z",
                    "duration_min": i * 3,
                    "files_touched": i,
                    "tool_calls": i * 5,
                    "checkpoints": 0,
                    "pivots": 0,
                    "friction": [],
                    "outcome": "success"
                }) + "\n")

        else:
            print(f"Unknown mode: {mode}", file=sys.stderr)
            sys.exit(1)

    total = sum(1 for _ in open(out_file))
    print(f"Generated {total} lines in {out_file}", file=sys.stderr)


if __name__ == "__main__":
    main()
