#!/usr/bin/env python3
"""Regression matrix for v0.2.7 P0/P1 shadow fusion invariants."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-fusion").read_text()

GALAXY = "com.gitvdemo.video"
GALAXY_PLAYER = "com.gala.video.app.player.PlayerActivity"
MANGO = "com.hunantv.license"
MANGO_ACTIVITY = "com.hunantv.imgo.activity.MainActivity"
TENCENT = "com.ktcp.video"
TENCENT_SHARED = "com.ktcp.video.activity.onepage.HomeSingleTaskActivity"

with tempfile.TemporaryDirectory(prefix="tvguard-fusion-matrix-") as folder:
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

    def run(seq, epoch, pkg, activity, audio, pps, shadow,
            adaptive_state, adaptive_reason, pause_hint, pause_score,
            active_floor=138):
        args = [
            "dash", str(target), str(epoch), str(epoch), str(seq), pkg, activity,
            str(audio), "1", str(pps), shadow, adaptive_state, "95",
            adaptive_reason, pause_hint, str(pause_score), str(active_floor),
        ]
        out = subprocess.check_output(args, text=True).strip().split()
        assert len(out) == 3, out
        return out[0], out[1], int(out[2])

    # P0: previously observed Mango 576p low-rate/bursty sequence must NEVER be
    # converted into paused solely because N1 calls it idle/idle_overlap.
    # Mango Activity semantics are not yet validated, so conservative unknown
    # is the required outcome for these low-rate windows.
    reset()
    mango_pps = [
        26, 3, 23, 4, 24, 2, 18, 10, 16, 15, 11, 35, 3,
        25, 2, 41, 2, 41, 2, 39, 3, 32, 22, 39, 17,
    ]
    for i, pps in enumerate(mango_pps, 1):
        state, candidate, streak = run(
            i, 1000 + i * 10, MANGO, MANGO_ACTIVITY, 1, pps, "idle",
            "idle", "stable_low", "idle_overlap", 60)
        assert state == "unknown", (i, pps, state, candidate, streak)
        assert candidate == "video_app_context_unresolved"
        assert streak == 0

    # A second real low-bitrate regime that sometimes reaches medium/high PPS
    # is also protected unless there is explicit clear-current playback.
    reset()
    mango_tcpish = [
        69, 163, 116, 59, 76, 87, 75, 84, 70, 148, 48, 77,
        104, 167, 105, 120, 114, 75, 64, 67, 40, 73, 46, 41,
        72, 52, 69, 88, 134, 55,
    ]
    for i, pps in enumerate(mango_tcpish, 1):
        state, candidate, streak = run(
            i, 2000 + i * 10, MANGO, MANGO_ACTIVITY, 1, pps, "unknown",
            "ambiguous", "overlap", "none", 0)
        assert state == "unknown", (i, pps, state, candidate, streak)
        assert candidate == "video_app_context_unresolved"
        assert streak == 0

    # Once current network evidence is explicitly clear, an unvalidated video
    # app may be reported as playing because this direction cannot grant free
    # time and is therefore conservative for billing.
    reset()
    assert run(
        1, 3000, MANGO, MANGO_ACTIVITY, 1, 180, "unknown",
        "active", "clear_current", "none", 0
    )[:2] == ("playing", "playing_confirmed_network_unvalidated_activity")

    # Galaxy low-rate PlayerActivity + idle_overlap is the critical false-pause
    # regression: repeated windows still must not accumulate pause streak.
    reset()
    for i, pps in enumerate((59, 61, 58, 63, 55, 60, 57), 1):
        state, candidate, streak = run(
            i, 4000 + i * 10, GALAXY, GALAXY_PLAYER, 1, pps, "idle",
            "idle", "stable_low", "idle_overlap", 60)
        assert state == "unknown"
        assert candidate == "player_idle_overlap_unresolved"
        assert streak == 0

    # Tencent shared Activity remains unresolved even with a strong pause hint.
    reset()
    for i in range(1, 5):
        state, candidate, streak = run(
            i, 5000 + i * 10, TENCENT, TENCENT_SHARED, 0, 96, "unknown",
            "active", "active_votes", "high_ratio_pause", 95)
        assert state == "unknown"
        assert candidate == "tencent_shared_activity_unresolved"
        assert streak == 0

print("v0.2.7 fusion matrix: Mango 576p + Galaxy low-rate + Tencent shared Activity PASS")
