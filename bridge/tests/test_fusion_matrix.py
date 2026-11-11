#!/usr/bin/env python3
"""Regression matrix using real observed traffic shapes but anonymous app identities."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-fusion").read_text()

PKG = "com.example.genericvideo"
PLAYER = "com.example.genericvideo.RootTask"
BROWSE = "com.example.genericvideo.Browse"

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

    def run(seq, epoch, activity, audio, pps, shadow,
            adaptive_state, adaptive_reason, pause_hint, pause_score,
            active_floor=138, pkg=PKG):
        args = [
            "dash", str(target), str(epoch), str(epoch), str(seq), pkg, activity,
            str(audio), "1", str(pps), shadow, adaptive_state, "95",
            adaptive_reason, pause_hint, str(pause_score), str(active_floor),
        ]
        out = subprocess.check_output(args, text=True).strip().split()
        assert len(out) == 3, out
        return out[0], out[1], int(out[2])

    def learn(epoch=900):
        return run(1, epoch, PLAYER, 1, 180, "unknown",
                   "active", "clear_current", "none", 0)

    # First teach the engine that this arbitrary package/activity is genuinely
    # capable of playback. No brand/package whitelist is involved.
    reset()
    assert learn()[:2] == ("playing", "playing_confirmed_context_learned")

    # Real observed 576p-like UDP-heavy burst pattern: once the context is
    # learned as media, stable-low/idle-overlap must NEVER become paused.
    pps_a = [26,3,23,4,24,2,18,10,16,15,11,35,3,25,2,41,2,41,2,39,3,32,22,39,17]
    for i, pps in enumerate(pps_a, 2):
        state, candidate, streak = run(
            i, 900 + i * 10, PLAYER, 1, pps, "idle",
            "idle", "stable_low", "idle_overlap", 60)
        assert state == "unknown", (i, pps, state, candidate, streak)
        assert candidate == "learned_media_idle_overlap_unresolved"
        assert streak == 0

    # Real observed 576p-like TCP-heavy range. Even medium bursts must not
    # create pause without the learned pause signature.
    reset()
    learn(2000)
    pps_b = [69,163,116,59,76,87,75,84,70,148,48,77,104,167,105,120,114,75,64,67,40,73,46,41,72,52,69,88,134,55]
    for i, pps in enumerate(pps_b, 2):
        state, candidate, streak = run(
            i, 2000 + i * 10, PLAYER, 1, pps, "unknown",
            "ambiguous", "overlap", "none", 0)
        assert state == "unknown", (i, pps, state, candidate, streak)
        assert candidate in (
            "learned_media_context_audio_hint_on",
            "learned_media_context_unresolved",
        )
        assert streak == 0

    # A package that has never produced strong playback evidence cannot get a
    # free-time state just because pause hints happen to resemble old samples.
    reset()
    for i in range(1, 5):
        state, candidate, streak = run(
            i, 3000 + i * 10, "SomeActivity", 0, 9, "idle",
            "idle", "stable_low", "high_ratio_pause", 95,
            pkg="com.example.neverlearned")
        assert state == "unknown"
        assert candidate == "unlearned_package_pause_hint_ignored"
        assert streak == 0

    # Shared-Activity pattern: the exact same Activity can learn playback first,
    # then later become paused using only generic temporal evidence.
    reset()
    learn(4000)
    for i in (2, 3):
        assert run(i, 4000 + i * 10, PLAYER, 0, 96, "unknown",
                   "active", "active_votes", "high_ratio_pause", 95)[:2] == (
            "unknown", "pause_candidate_learned_context")
    assert run(4, 4040, PLAYER, 0, 96, "unknown",
               "active", "active_votes", "high_ratio_pause", 95)[:2] == (
        "paused", "paused_confirmed_learned_context")

    # Same learned package, different Activity, sustained no-audio idle:
    # generic app-side non-playing UI classification.
    reset()
    learn(5000)
    for i in (2, 3):
        assert run(i, 5000 + i * 10, BROWSE, 0, 8, "idle",
                   "idle", "stable_low", "idle_overlap", 60)[:2] == (
            "unknown", "app_nonplaying_warming")
    assert run(4, 5040, BROWSE, 0, 7, "idle",
               "idle", "stable_low", "idle_overlap", 60)[:2] == (
        "app_home", "app_nonplaying_confirmed")

print("v0.2.8 fusion matrix: anonymous real traffic shapes + generic context learning PASS")
