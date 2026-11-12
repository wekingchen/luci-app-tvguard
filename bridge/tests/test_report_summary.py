#!/usr/bin/env python3
"""Exercise app-agnostic bridge summary against a synthetic bounded RAM v3 ring."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-bridge-report").read_text()

with tempfile.TemporaryDirectory(prefix="tvguard-summary-") as folder:
    d = Path(folder)
    data = d / "soak-v3.csv"
    rows = [
        "1000,2,pkg,ctx,1,1,20,idle,ambiguous,50,overlap,bursty_pause,75,12,100,138,unknown,pause_candidate_learned_context,1,10,1000,1",
        "1010,2,pkg,ctx,1,1,18,idle,ambiguous,50,overlap,bursty_pause,75,11,100,138,unknown,pause_candidate_learned_context,2,11,1010,1",
        "1020,2,pkg,ctx,1,1,16,idle,ambiguous,50,overlap,bursty_pause,75,10,100,138,paused,paused_confirmed_learned_context,3,12,1020,1",
        "1030,2,pkg,ctx,1,1,150,playing,active,100,clear_current,none,0,120,150,138,playing,playing_confirmed_context_learned,0,13,1030,1",
        "1040,2,pkg,browse,0,1,8,idle,idle,95,stable_low,idle_overlap,60,7,8,138,unknown,app_nonplaying_warming,0,14,1040,1",
        "1050,2,pkg,browse,0,1,7,idle,idle,95,stable_low,idle_overlap,60,7,8,138,app_home,app_nonplaying_confirmed,0,15,1050,1",
        "1060,2,pkg,ctx,1,1,9,idle,idle,95,stable_low,idle_overlap,60,7,9,138,unknown,learned_media_idle_overlap_unresolved,0,16,1060,1",
        "1070,2,other,ctx,0,1,9,idle,idle,95,stable_low,high_ratio_pause,95,7,9,138,unknown,unlearned_package_pause_hint_ignored,0,17,1070,1",
        "1080,2,pkg,ctx,1,1,20,idle,ambiguous,50,overlap,bursty_pause,75,10,100,138,unknown,agent_process_restart_context_reset,0,1,1080,1",
        "1090,12,pkg,ctx,1,1,20,idle,ambiguous,50,overlap,bursty_pause,75,10,100,138,unknown,repeated_report_not_new_evidence,0,1,1080,0",
        "1100,69,unknown,unknown,unknown,unknown,unknown,unknown,unknown,0,unknown,unknown,0,0,0,0,unknown,agent_stale,0,1,1080,0",
    ]
    data.write_text("\n".join(rows) + "\n")

    script = source.replace("RAM=/var/run/tvguard-agent-bridge", f"RAM={d}")
    target = d / "report"
    target.write_text(script)
    target.chmod(0o755)

    out = subprocess.check_output(["dash", str(target), "summary"], text=True)
    got = dict(line.split("=", 1) for line in out.strip().splitlines())

    expected = {
        "schema": "v3",
        "rows": "11",
        "fresh_reports": "9",
        "repeated_rows": "1",
        "stale_rows": "1",
        "combined_playing": "1",
        "combined_paused": "1",
        "combined_app_home": "1",
        "combined_system_home": "0",
        "combined_unknown": "6",
        "pause_warming": "2",
        "pause_confirmed": "1",
        "pause_hold": "0",
        "media_idle_overlap_unresolved": "1",
        "app_nonplaying_warming": "1",
        "app_nonplaying_confirmed": "1",
        "unlearned_pause_ignored": "1",
        "agent_restart_reset": "1",
        "last_sample_epoch": "1100",
        "billing_effect": "none",
    }
    for key, value in expected.items():
        assert got.get(key) == value, (key, got.get(key), value, out)

print("bridge summary: generic learned-context counters PASS")
