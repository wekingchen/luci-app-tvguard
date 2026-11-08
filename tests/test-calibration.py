#!/usr/bin/env python3
"""Regression checks for the conservative, offline classifier report."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
analyzer = root / "scripts/evaluate-calibration.py"

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory, "calibration-v3.csv")
    rows = []
    # Three independent playing, idle, and paused sessions, eight 10-second
    # windows each. Paused traffic deliberately overlaps with playing.
    for session in range(1, 4):
        for label in ("playing", "app_home", "paused"):
            for i in range(8):
                packets = {
                    "playing": 180 + (session % 2) * 4 + i,
                    "app_home": 8 + (session % 2) * 2 + (i % 3),
                    "paused": 180 + (i % 6),
                }[label]
                rows.append(f"{1730000000 + session * 100 + i * 10},"
                            f"{session * 100}-{label.count('a')},"
                            f"{label},tencent,{packets},{packets // 5},"
                            f"{packets - packets // 5},{packets * 400}")
    # Ensure session IDs are unique per labelled scene, as in the controller.
    rows = []
    sid = 0
    for label in ("playing", "app_home", "paused"):
        for session in range(3):
            sid += 1
            for i in range(8):
                packets = (180 + i + session if label != "app_home" else 7 + i % 3)
                rows.append(f"{1730000000+sid*130+i*10},{sid}-1,{label},"
                            f"tencent,{packets},{packets // 5},"
                            f"{packets - packets // 5},{packets * 400}")
    path.write_text("\n".join(rows) + "\n", encoding="utf-8")
    parsed = json.loads(subprocess.check_output(
        [sys.executable, str(analyzer), str(path)], text=True))
    assert parsed["automatic_exemption_enabled"] is False
    report = {x["idle_label"]: x for x in parsed["results"]}
    assert report["app_home"]["verdict"] == "separable_shadow_only", report
    assert report["paused"]["verdict"] == "overlap_or_unstable", report
    # Losing one independent session must invalidate evaluation.
    path.write_text("\n".join(x for x in rows
                              if not x.split(",")[1].startswith("3-")) + "\n",
                    encoding="utf-8")
    parsed = json.loads(subprocess.check_output(
        [sys.executable, str(analyzer), str(path)], text=True))
    report = {x["idle_label"]: x for x in parsed["results"]}
    assert report["app_home"]["verdict"] == "insufficient", report

print("PASS: cross-session evidence gate rejects overlap and insufficient samples")
