#!/usr/bin/env python3
"""Run the actual RAM-only shadow v2 collector through new/repeated/stale reports.

No router paths are touched; timing is shortened for CI.
"""
import os
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-bridge-soak").read_text()

with tempfile.TemporaryDirectory(prefix="tvguard-soak-v2-") as folder:
    d = Path(folder)
    latest = d / "latest"
    latest.write_text("synthetic\n")
    status_file = d / "synthetic-status"

    def online(seq, received, age=3):
        return (
            "agent=online\n"
            f"age_seconds={age}\n"
            f"received_epoch={received}\n"
            f"report_seq={seq}\n"
            "package=com.gitvdemo.video\n"
            "activity=com.gala.video.app.player.PlayerActivity\n"
            "audio_active=0\n"
            "screen_on=1\n"
            "network_pps=476\n"
            "network_shadow=unknown\n"
            "combined_candidate=player_state_unresolved_audio_hint_off\n"
            "billing_effect=none\n"
        )
    def stale(seq, received):
        return (
            "agent=stale\nage_seconds=69\n"
            f"last_received_epoch={received}\n"
            f"last_report_seq={seq}\n"
            "activity=unknown\nbilling_effect=none\n"
        )

    # Replace only runtime dependencies with fixed synthetic inputs.
    script = (source.replace("RAM=/var/run/tvguard-agent-bridge", f"RAM={d}")
             .replace("/usr/libexec/tvguard-agent-bridge-report status",
                      f"cat {status_file}")
             .replace("sleep 10", "sleep 0.12"))
    run_file = d / "soak"
    run_file.write_text(script)
    status_file.write_text(online(7, 1794319631))
    proc = subprocess.Popen(["dash", str(run_file)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    try:
        time.sleep(0.45)
        status_file.write_text(online(8, 1794319643))
        time.sleep(0.27)
        status_file.write_text(stale(8, 1794319643))
        time.sleep(0.27)
        status_file.write_text(online(1, 1794319700))
        time.sleep(0.27)
    finally:
        proc.terminate()
        try:
            proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate(timeout=3)
    data = d / "soak-v2.csv"
    assert data.exists(), "no synthetic RAM sample saved"
    rows = [r.split(",") for r in data.read_text().splitlines()]
    assert all(len(r) == 12 for r in rows), rows
    assert any(r[9] == "7" and r[11] == "1" for r in rows), rows
    assert any(r[8] == "repeated_report_not_new_evidence"
               and r[9] == "7" and r[11] == "0" for r in rows), rows
    assert any(r[9] == "8" and r[11] == "1" for r in rows), rows
    assert any(r[8] == "agent_stale" and r[11] == "0" for r in rows), rows
    assert any(r[8] == "agent_process_restart_suspected"
               and r[9] == "1" and r[11] == "1" for r in rows), rows
    assert len(rows) < 180
print("RAM shadow v2: fresh vs repeat vs stale report handling PASS")
