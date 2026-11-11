#!/usr/bin/env python3
"""Exercise v0.2.7 RAM-only Agent/N1 temporal fusion with real shell code."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-fusion").read_text()

GALAXY = "com.gitvdemo.video"
PLAYER = "com.gala.video.app.player.PlayerActivity"
HOME = "com.gala.video.app.epg.HomeActivity"
TENCENT = "com.ktcp.video"
TENCENT_SHARED = "com.ktcp.video.activity.onepage.HomeSingleTaskActivity"

with tempfile.TemporaryDirectory(prefix="tvguard-fusion-") as folder:
    d = Path(folder)
    script = source.replace("RAM=/var/run/tvguard-agent-bridge", f"RAM={d}")
    target = d / "fusion"
    target.write_text(script)
    target.chmod(0o755)

    def reset():
        for name in ("fusion.state", "fusion.lock"):
            p = d / name
            if p.is_file():
                p.unlink()
            elif p.is_dir():
                p.rmdir()

    def run(seq, seen, pkg=GALAXY, activity=PLAYER, audio=1, screen=1,
            pps=20, shadow="idle", adaptive_state="ambiguous",
            adaptive_score=50, adaptive_reason="overlap",
            pause_hint="bursty_pause", pause_score=75, active_floor=100):
        args = [
            "dash", str(target),
            str(seen), str(seen), str(seq), pkg, activity,
            str(audio), str(screen), str(pps), shadow,
            adaptive_state, str(adaptive_score), adaptive_reason,
            pause_hint, str(pause_score), str(active_floor),
        ]
        out = subprocess.check_output(args, text=True).strip().split()
        assert len(out) == 3, out
        return out[0], out[1], int(out[2])

    # Directly observable UI states.
    reset()
    assert run(1, 100, pkg="com.mitv.tvhome",
               activity="com.mitv.tvhome.MainActivityUserMode",
               pause_hint="none", pause_score=0)[:2] == (
        "system_home", "system_home_confirmed")
    assert run(2, 110, activity=HOME,
               pause_hint="none", pause_score=0)[:2] == (
        "app_home", "app_home_confirmed_galaxy")

    # Galaxy PlayerActivity + strong pause hint must be sustained for 3 NEW
    # Agent reports. audio_active=1 intentionally does not veto a real pause.
    reset()
    assert run(10, 200) == ("unknown", "pause_candidate_warming", 1)
    assert run(11, 210) == ("unknown", "pause_candidate_warming", 2)
    assert run(12, 220) == ("paused", "paused_confirmed_temporal", 3)

    # Re-reading the same report cannot manufacture another temporal vote.
    assert run(12, 220) == ("paused", "paused_confirmed_temporal", 3)

    # One missing hint is held to avoid flicker; a second missing fresh report
    # releases pause unless strong playback appears first.
    assert run(13, 230, pause_hint="none", pause_score=0) == (
        "paused", "paused_temporal_hold", 3)
    assert run(14, 240, pause_hint="none", pause_score=0) == (
        "unknown", "player_context_unresolved", 0)

    # Strong current network evidence exits pause immediately.
    reset()
    run(20, 300)
    run(21, 310)
    assert run(22, 320) == ("paused", "paused_confirmed_temporal", 3)
    assert run(23, 330, pps=150, shadow="unknown",
               adaptive_state="active", adaptive_score=100,
               adaptive_reason="clear_current",
               pause_hint="high_ratio_pause", pause_score=95,
               active_floor=100) == (
        "playing", "playing_confirmed_network", 0)

    # P0 guard: idle_overlap is never sufficient to call PlayerActivity paused,
    # even for repeated very-low-PPS windows.
    reset()
    for i in range(1, 8):
        state, candidate, streak = run(
            i, 400 + i * 10, pps=9, shadow="idle",
            adaptive_state="idle", adaptive_score=95,
            adaptive_reason="stable_low",
            pause_hint="idle_overlap", pause_score=60, active_floor=100)
        assert state == "unknown", (i, state, candidate, streak)
        assert candidate == "player_idle_overlap_unresolved"
        assert streak == 0

    # Agent process restart must discard accumulated player temporal confidence.
    reset()
    run(30, 600)
    run(31, 610)
    assert run(32, 620)[0] == "paused"
    assert run(1, 630) == (
        "unknown", "agent_process_restart_context_reset", 0)

    # Tencent's real shared HomeSingleTaskActivity cannot be treated as App-home
    # or pause: it is observed during both actual playback and pause.
    reset()
    assert run(1, 700, pkg=TENCENT, activity=TENCENT_SHARED,
               audio=0, pps=96, shadow="unknown",
               adaptive_state="active", adaptive_score=95,
               adaptive_reason="active_votes",
               pause_hint="high_ratio_pause", pause_score=95,
               active_floor=138) == (
        "unknown", "tencent_shared_activity_unresolved", 0)

print("v0.2.7 temporal fusion: pause hysteresis + low-bitrate safety PASS")
