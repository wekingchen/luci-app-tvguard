#!/usr/bin/env python3
"""Conservative, OFFLINE calibration separability report.

This script deliberately does not generate firewall rules or automatic
"verified idle" exemptions. Aggregate PPS alone is not a screen-state signal.
"""
import argparse
import csv
import json
import re
from collections import defaultdict
from itertools import product
from pathlib import Path

FEATURES = ("pps", "tcp_pps", "udp_pps", "bytes_per_second")
LABELS = ("app_home", "paused")
VALID_SCENES = {"playing", "paused", "app_home", "system_home", "sleep"}
VALID_APPS = {"tencent", "iqiyi", "mango", "other", "general", "system"}


def read_sessions(filename):
    groups = defaultdict(list)
    with Path(filename).open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        for line, row in enumerate(reader, 1):
            if not row:
                continue
            if len(row) != 8:
                raise ValueError(f"line {line}: expected 8 columns, got {len(row)}")
            timestamp, session, scene, app, *numbers = row
            package_like = bool(re.fullmatch(r"[A-Za-z0-9._$]+", app))
            if scene not in VALID_SCENES or not (app in VALID_APPS or package_like):
                raise ValueError(f"line {line}: unsupported scene/app")
            if not session or any(ch not in "0123456789-" for ch in session):
                raise ValueError(f"line {line}: bad session identifier")
            values = {}
            for key, value in zip(FEATURES, numbers):
                n = int(value)
                if n < 0:
                    raise ValueError(f"line {line}: negative counter")
                values[key] = n
            groups[(app, scene, session)].append(values)
    return groups


def evaluate_pair(groups, app, idle, min_sessions=3, min_samples=6):
    def collect(scene):
        result = {}
        for (a, lab, sid), rows in groups.items():
            if a == app and lab == scene and len(rows) >= min_samples:
                result[sid] = rows
        return result

    play = collect("playing")
    rest = collect(idle)
    out = dict(app=app, idle_label=idle, playing_sessions=len(play),
               idle_sessions=len(rest), verdict="insufficient", candidates=[])
    if len(play) < min_sessions or len(rest) < min_sessions:
        return out

    # Require validation on every pair of held-out *sessions*: no sample from
    # those sessions influences the candidate threshold in that fold.
    for key in FEATURES:
        for direction in ("idle_lower", "idle_higher"):
            folds_ok = True
            margins = []
            for p_hold, i_hold in product(play, rest):
                p_train = [row[key] for sid, rows in play.items()
                           if sid != p_hold for row in rows]
                i_train = [row[key] for sid, rows in rest.items()
                           if sid != i_hold for row in rows]
                if not p_train or not i_train:
                    folds_ok = False
                    break
                if direction == "idle_lower":
                    lo, hi = max(i_train), min(p_train)
                    gap = hi - lo
                    valid = max(row[key] for row in rest[i_hold]) < (lo + hi) / 2 < min(
                        row[key] for row in play[p_hold])
                else:
                    lo, hi = max(p_train), min(i_train)
                    gap = hi - lo
                    valid = max(row[key] for row in play[p_hold]) < (lo + hi) / 2 < min(
                        row[key] for row in rest[i_hold])
                # Require large separation: at least 10 packets/s for packet
                # features and a conservative 4 KiB/s for byte rate.
                required_gap = 4096 if key == "bytes_per_second" else 10
                if gap < required_gap or not valid:
                    folds_ok = False
                    break
                margins.append(gap)
            if folds_ok:
                out["candidates"].append({
                    "feature": key, "direction": direction,
                    "minimum_training_gap": min(margins)
                })
    out["verdict"] = "separable_shadow_only" if out["candidates"] else "overlap_or_unstable"
    return out


def main():
    parser = argparse.ArgumentParser(description="TV Guard calibration report (no auto-exemptions)")
    parser.add_argument("csv", help="calibration-v3.csv exported from N1")
    parser.add_argument("--min-sessions", type=int, default=3)
    args = parser.parse_args()
    if args.min_sessions < 3:
        parser.error("at least 3 independent sessions are required")
    groups = read_sessions(args.csv)
    apps = sorted({key[0] for key in groups if key[0] != "system"})
    result = [
        evaluate_pair(groups, app, idle, min_sessions=args.min_sessions)
        for app in apps
        for idle in LABELS
        if any(k[0] == app for k in groups)
    ]
    output = {
        "schema": "tvguard-shadow-evaluation-v1",
        "automatic_exemption_enabled": False,
        "note": "Pure traffic patterns cannot prove a TV foreground UI; candidates need real-world validation.",
        "results": result,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
