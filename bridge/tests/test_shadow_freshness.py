#!/usr/bin/env python3
"""Run the actual RAM-only v3 collector through new/repeated/stale reports."""
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-bridge-soak").read_text()

with tempfile.TemporaryDirectory(prefix="tvguard-soak-v3-") as folder:
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
            "audio_active=1\n"
            "screen_on=1\n"
            "network_pps=24\n"
            "network_shadow=idle\n"
            "adaptive_state=ambiguous\n"
            "adaptive_score=50\n"
            "adaptive_reason=overlap\n"
            "pause_hint=bursty_pause\n"
            "pause_score=75\n"
            "adaptive_p50=11\n"
            "adaptive_p90=112\n"
            "adaptive_active_floor=138\n"
            "combined_state=unknown\n"
            "combined_candidate=pause_candidate_warming\n"
            "fusion_pause_streak=2\n"
            "billing_effect=none\n"
        )

    def stale(seq, received):
        return (
            "agent=stale\nage_seconds=69\n"
            f"last_received_epoch={received}\n"
            f"last_report_seq={seq}\n"
            "activity=unknown\n"
            "combined_state=unknown\n"
            "combined_candidate=agent_stale\n"
            "fusion_pause_streak=0\n"
            "billing_effect=none\n"
        )

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

    data = d / "soak-v3.csv"
    assert data.exists(), "no synthetic RAM sample saved"
    rows = [r.split(",") for r in data.read_text().splitlines()]
    assert all(len(r) == 22 for r in rows), rows
    assert any(r[19] == "7" and r[21] == "1" for r in rows), rows
    assert any(r[17] == "repeated_report_not_new_evidence"
               and r[19] == "7" and r[21] == "0" for r in rows), rows
    assert any(r[19] == "8" and r[21] == "1" for r in rows), rows
    assert any(r[17] == "agent_stale" and r[21] == "0" for r in rows), rows
    assert any(r[17] == "agent_process_restart_suspected"
               and r[19] == "1" and r[21] == "1" for r in rows), rows
    assert len(rows) < 180

print("RAM shadow v3: fusion evidence + fresh/repeat/stale handling PASS")
