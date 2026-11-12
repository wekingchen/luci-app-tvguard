#!/usr/bin/env python3
"""Test whether TV Guard billing hints generalize safely to unseen video apps.

Hold out ALL samples of one complete app, train the actual shell classifier on
the OTHER apps, and evaluate the never-seen app. This diagnostic NEVER changes
router settings, time accounting, permissions or automatic exemptions.

Requirements: >=3 independently labelled video apps, and >=3 sessions with
>=6 windows for each scene/app (playing, paused, app_home).
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

SCENES = ("playing", "paused", "app_home")
KNOWN_VIDEO_APPS = ("tencent", "iqiyi", "mango")
VALID_APPS = set(KNOWN_VIDEO_APPS) | {"general", "other", "system"}
VALID_SCENES = set(SCENES) | {"system_home", "sleep"}


def parse_rows(path: Path):
    """Normalize legacy v3 or Agent-enriched v5 into v3-shaped rows.

    v5 legacy columns (14) end at bps. r4 rows add:
      usage_access,foreground_source,foreground_status,context_quality

    Only fresh rows with a known package AND full package+Activity context may
    establish an automatic app identity for cross-app billing safety claims.
    """
    rows = []
    source_schema = None
    with path.open(encoding="utf-8", newline="") as handle:
        for number, parts in enumerate(csv.reader(handle), 1):
            if not parts:
                continue
            if len(parts) == 8:
                schema = "v3"
                stamp, session, scene, app, *metrics = parts
                package_like = bool(re.fullmatch(r"[A-Za-z0-9._$]+", app))
                if scene not in VALID_SCENES or not (app in VALID_APPS or package_like):
                    raise ValueError(f"line {number}: invalid scene/app label")
            elif len(parts) in (14, 18):
                schema = "v5"
                base = parts[:14]
                (stamp, session, scene, agent_state, _agent_age, package,
                 activity, _audio, _screen, _seq, *metrics) = base
                context_quality = parts[17] if len(parts) == 18 else (
                    "full" if package not in ("", "unknown") and
                    activity not in ("", "unknown") else "unknown")
                if scene not in VALID_SCENES:
                    raise ValueError(f"line {number}: invalid scene label")
                if agent_state != "fresh" or context_quality != "full":
                    continue
                if not package or package == "unknown" or "," in package:
                    continue
                app = package
            else:
                raise ValueError(
                    f"line {number}: expected v3 (8) or v5 (14/18) CSV fields")
            if source_schema is None:
                source_schema = schema
            elif source_schema != schema:
                raise ValueError("mixed v3/v5 rows are not supported")
            if not session.replace("-", "").isdigit() or session.count("-") != 1:
                raise ValueError(f"line {number}: invalid session id")
            if not stamp.isdigit() or not all(x.isdigit() for x in metrics):
                raise ValueError(f"line {number}: invalid telemetry")
            rows.append((stamp, session, scene, app, *metrics))
    return rows, source_schema or "unknown"


def complete_app(app, rows):
    for scene in SCENES:
        sessions = defaultdict(int)
        for row in rows:
            if row[3] == app and row[2] == scene:
                sessions[row[1]] += 1
        if sum(n >= 6 for n in sessions.values()) < 3:
            return False
    return True


def evaluate(rows, script_path, input_schema="v3"):
    candidates = sorted({
        row[3] for row in rows
        if row[2] in SCENES and row[3] not in {"general", "other", "system"}
    })
    apps = [app for app in candidates if complete_app(app, rows)]
    result = {
        "schema": "tvguard-cross-app-billing-v3",
        "input_schema": input_schema,
        "billing_policy": "verified_idle_after_30s_hysteresis",
        "generic_idle_validation_ready": len(apps) >= 3,
        "video_apps_with_complete_sessions": apps,
        "verdict": "insufficient_cross_app_validation",
        "folds": [],
        "overall": {
            "idle_hint_correct": 0,
            "charge_correct": 0,
            "conservative_idle_miss": 0,
            "dangerous_idle_false_hints": 0
        },
    }
    # Need at least two DIFFERENT apps to train, and one entirely unseen app to
    # validate. No statistical generalization claim from one labelled app.
    if len(apps) < 3:
        return result

    with tempfile.TemporaryDirectory(prefix="tvguard-validation-") as d:
        directory = Path(d)
        csv_path = directory / "calibration-v3.csv"
        shadow = directory / "tvguard-shadow"
        source = script_path.read_text(encoding="utf-8")
        durable_anchor = (
            'DATA=/usr/libexec/tvguard-data\n'
            'DIR="$("$DATA" root)"\n'
            'CSV="$DIR/calibration-v3.csv"'
        )
        legacy_anchor = "CSV=/etc/tvguard/calibration-v3.csv"
        if source.count(durable_anchor) == 1:
            source = source.replace(durable_anchor, "CSV=" + str(csv_path), 1)
        elif source.count(legacy_anchor) == 1:
            source = source.replace(legacy_anchor, "CSV=" + str(csv_path), 1)
        else:
            raise ValueError("shadow script no longer exposes an injectable calibration path")
        shadow.write_text(source, encoding="utf-8")

        for holdout in apps:
            train = [row for row in rows if row[3] != holdout]
            train_apps = sorted({
                row[3] for row in train
                if row[2] in SCENES and row[3] not in {"general", "other", "system"}
            })
            # tvguard-shadow keeps its stable v3 schema with three symbolic app
            # slots. Map real Agent package identities into those slots only
            # inside this temporary evaluator; production data remains generic.
            slot_map = {
                app: KNOWN_VIDEO_APPS[i]
                for i, app in enumerate(train_apps[:len(KNOWN_VIDEO_APPS)])
            }
            normalized = []
            for row in train:
                stamp, session, scene, app, *metrics = row
                if scene == "system_home":
                    label = "system"
                else:
                    label = slot_map.get(app, app if app in VALID_APPS else "other")
                normalized.append((stamp, session, scene, label, *metrics))
            csv_path.write_text(
                "\n".join(",".join(row) for row in normalized) + "\n",
                encoding="utf-8",
            )
            counts = Counter()
            for row in rows:
                if row[3] != holdout or row[2] not in SCENES:
                    continue
                observed = subprocess.run(
                    ["sh", str(shadow), *row[4:]],
                    check=True, capture_output=True, text=True,
                ).stdout.strip().split()
                prediction = observed[0] if len(observed) == 3 else "unknown"
                actual = row[2]
                idle_prediction = prediction in ("idle", "paused", "app_home", "system_home")
                if actual == "playing":
                    if idle_prediction:
                        counts["dangerous_idle_false_hints"] += 1
                    else:
                        # playing or unknown both remain billable, hence safe.
                        counts["charge_correct"] += 1
                else:
                    # paused/app_home are equivalent for billing. Missing an
                    # idle hint is conservative over-charging, not a bypass.
                    if idle_prediction:
                        counts["idle_hint_correct"] += 1
                    else:
                        counts["conservative_idle_miss"] += 1
            fold = {"held_out_app": holdout, **{
                key: counts[key] for key in result["overall"]}}
            result["folds"].append(fold)
            for key in result["overall"]:
                result["overall"][key] += counts[key]

    # Even a good holdout test only shows performance on these representative
    # apps and known conditions. Never equate this to proof of TV foreground.
    result["verdict"] = (
        "observed_zero_dangerous_idle_false_hints"
        if result["overall"]["dangerous_idle_false_hints"] == 0
        else "dangerous_idle_false_hints_observed"
    )
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Leave-one-video-app-out billing safety test")
    parser.add_argument("csv", help="export of N1 calibration-v3.csv")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    rows, input_schema = parse_rows(Path(args.csv))
    report = evaluate(
        rows,
        root / "root/usr/libexec/tvguard-shadow",
        input_schema=input_schema,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"evaluation failed: {exc}", file=sys.stderr)
        sys.exit(1)
