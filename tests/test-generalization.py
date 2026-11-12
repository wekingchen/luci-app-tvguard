#!/usr/bin/env python3
"""Test generic inference using an unseen app, not simply one known app label."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
evaluator = root / "scripts/evaluate-generalization.py"
scenes = {
    "playing": (180, 30, 150, 65000),
    "paused": (85, 5, 80, 30000),
    "app_home": (30, 1, 28, 16000),
}


def make_rows(apps, confuse=False):
    rows = []
    sid = 0
    for app in apps:
        for scene, metrics in scenes.items():
            for run in range(3):
                sid += 1
                for window in range(8):
                    values = metrics
                    # Simulate a novel app whose PLAYBACK traffic looks like
                    # known app-home traffic. This is the dangerous direction:
                    # an unseen player must never receive a free idle hint.
                    if confuse and app == "mango" and scene == "playing":
                        values = scenes["app_home"]
                    p, tcp, udp, by = values
                    rows.append(
                        f"{1730000000+sid*130+window*10},{sid}-1,"
                        f"{scene},{app},{p+window%2},{tcp+window%2},"
                        f"{udp+window%2},{by+window*20}"
                    )
    return "\n".join(rows) + "\n"


def make_v5_rows(packages):
    rows = []
    sid = 1000
    seq = 0
    for package in packages:
        for scene, metrics in scenes.items():
            for run in range(3):
                sid += 1
                for window in range(8):
                    seq += 1
                    p, tcp, udp, by = metrics
                    stamp = 1740000000 + sid * 130 + window * 10
                    audio = 1 if scene == "playing" else 0
                    activity = package + (".PlayerActivity" if scene != "app_home" else ".HomeActivity")
                    rows.append(
                        f"{stamp},{sid}-1,{scene},fresh,2,{package},{activity},"
                        f"{audio},1,{seq},{p+window%2},{tcp+window%2},"
                        f"{udp+window%2},{by+window*20}"
                    )
    return "\n".join(rows) + "\n"


def make_v5_extended_package_only(packages):
    rows = []
    sid = 2000
    seq = 0
    for package in packages:
        for scene, metrics in scenes.items():
            for run in range(3):
                sid += 1
                for window in range(8):
                    seq += 1
                    p, tcp, udp, by = metrics
                    stamp = 1750000000 + sid * 130 + window * 10
                    rows.append(
                        f"{stamp},{sid}-1,{scene},fresh,2,{package},unknown,"
                        f"1,1,{seq},{p},{tcp},{udp},{by},allowed,usage_stats,"
                        f"package_only,package_only"
                    )
    return "\n".join(rows) + "\n"


def check(csv_path):
    return json.loads(subprocess.check_output(
        [sys.executable, str(evaluator), str(csv_path)],
        text=True,
    ))


with tempfile.TemporaryDirectory() as d:
    csv_path = Path(d) / "calibration-v3.csv"
    csv_path.write_text(make_rows(("tencent", "iqiyi")), encoding="utf-8")
    report = check(csv_path)
    assert report["verdict"] == "insufficient_cross_app_validation", report
    assert report["generic_idle_validation_ready"] is False

    csv_path.write_text(
        make_rows(("tencent", "iqiyi", "mango")), encoding="utf-8")
    report = check(csv_path)
    assert report["verdict"] == "observed_zero_dangerous_idle_false_hints", report
    assert len(report["folds"]) == 3, report
    assert report["generic_idle_validation_ready"] is True, report
    assert report["overall"]["idle_hint_correct"] > 0, report
    assert report["overall"]["charge_correct"] > 0, report
    assert report["overall"]["dangerous_idle_false_hints"] == 0, report

    v5_path = Path(d) / "calibration-v5.csv"
    v5_packages = ("com.alpha.video", "com.beta.video", "com.gamma.video")
    v5_path.write_text(make_v5_rows(v5_packages), encoding="utf-8")
    report = check(v5_path)
    assert report["input_schema"] == "v5", report
    assert report["generic_idle_validation_ready"] is True, report
    assert {fold["held_out_app"] for fold in report["folds"]} == set(v5_packages), report
    assert report["overall"]["dangerous_idle_false_hints"] == 0, report

    v5_path.write_text(
        make_v5_extended_package_only(v5_packages), encoding="utf-8")
    report = check(v5_path)
    assert report["input_schema"] == "unknown", report
    assert report["generic_idle_validation_ready"] is False, report

    csv_path.write_text(
        make_rows(("tencent", "iqiyi", "mango"), confuse=True), encoding="utf-8")
    report = check(csv_path)
    assert report["verdict"] == "dangerous_idle_false_hints_observed", report
    assert report["overall"]["dangerous_idle_false_hints"] > 0, report
    assert report["generic_idle_validation_ready"] is True

print("PASS: leave-one-app-out distinguishes conservative misses from dangerous free-play hints")
