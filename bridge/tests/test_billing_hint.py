#!/usr/bin/env python3
"""Conservative formal-billing contract: only explicit homes may grant free time."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
fusion_source = (root / "root/usr/libexec/tvguard-agent-fusion").read_text()
hint_source = (root / "root/usr/libexec/tvguard-agent-billing-hint").read_text()

PKG = "com.example.media"
PLAYER = "com.example.media.RootTask"
BROWSE = "com.example.media.Browse"

with tempfile.TemporaryDirectory(prefix="tvguard-billing-hint-") as folder:
    d = Path(folder)
    fusion = d / "fusion"
    fusion.write_text(fusion_source.replace(
        "RAM=/var/run/tvguard-agent-bridge", f"RAM={d}"))
    fusion.chmod(0o755)

    hint = d / "billing-hint"
    text = hint_source.replace(
        "RAM=/var/run/tvguard-agent-bridge", f"RAM={d}")
    text = text.replace(
        "FUSION=/usr/libexec/tvguard-agent-fusion", f"FUSION={fusion}")
    hint.write_text(text)
    hint.chmod(0o755)

    latest = d / "latest"

    def put(seq, seen, pkg, activity, audio=1, screen=1):
        latest.write_text(
            f"{seen}|{pkg}|{activity}|{audio}|{screen}|{seen*1000}|{seq}\n")

    def run(now, pps=20, shadow="unknown", adaptive_state="ambiguous",
            adaptive_score=50, adaptive_reason="overlap",
            pause_hint="none", pause_score=0, active_floor=138):
        out = subprocess.check_output([
            "dash", str(hint), str(now), str(pps), shadow,
            adaptive_state, str(adaptive_score), adaptive_reason,
            pause_hint, str(pause_score), str(active_floor),
        ], text=True).strip()
        parts = out.split()
        assert len(parts) == 2, out
        return tuple(parts)

    # Missing Agent context must never grant free time.
    assert run(100) == ("charge", "unknown")

    # A fresh platform launcher is the narrow direct system-home exemption.
    put(1, 100, "com.mitv.tvhome", "com.mitv.tvhome.MainActivityUserMode", audio=0)
    assert run(100, pps=30) == ("free", "system_home")

    # An arbitrary never-learned app remains chargeable even with pause-like traffic.
    put(2, 200, "com.example.other", "com.example.other.Page", audio=0)
    assert run(200, pps=9, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low",
               pause_hint="high_ratio_pause", pause_score=95) == (
        "charge", "unknown")

    # Strong playback learns a generic media context, but playback itself charges.
    put(10, 300, PKG, PLAYER, audio=1)
    assert run(300, pps=180, adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current") == (
        "charge", "playing")

    # Same learned package, different Activity, sustained no-audio + trusted
    # low/non-playing evidence becomes app_home only after temporal confirmation.
    for seq, now in ((11, 310), (12, 320)):
        put(seq, now, PKG, BROWSE, audio=0)
        assert run(now, pps=8, shadow="idle", adaptive_state="idle",
                   adaptive_score=95, adaptive_reason="stable_low",
                   pause_hint="idle_overlap", pause_score=60) == (
            "charge", "unknown")
    put(13, 330, PKG, BROWSE, audio=0)
    assert run(330, pps=7, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low",
               pause_hint="idle_overlap", pause_score=60) == (
        "free", "app_home")

    # Pause remains Shadow-only research. Even a confirmed generic paused state
    # is explicitly chargeable under the conservative formal policy.
    put(20, 400, PKG, PLAYER, audio=1)
    assert run(400, pps=180, adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current") == (
        "charge", "playing")
    for seq, now in ((21, 460), (22, 470)):
        put(seq, now, PKG, PLAYER, audio=0)
        assert run(now, pps=50, adaptive_state="ambiguous",
                   adaptive_score=50, adaptive_reason="overlap",
                   pause_hint="high_ratio_pause", pause_score=95) == (
            "charge", "unknown")
    put(23, 480, PKG, PLAYER, audio=0)
    assert run(480, pps=45, adaptive_state="ambiguous",
               adaptive_score=50, adaptive_reason="overlap",
               pause_hint="high_ratio_pause", pause_score=95) == (
        "charge", "paused")

    # A launcher report older than the 20-second billing freshness gate fails closed.
    put(30, 500, "com.mitv.tvhome", "com.mitv.tvhome.MainActivityUserMode", audio=0)
    assert run(521, pps=10) == ("charge", "unknown")

print("billing hint: only system_home/app_home free; pause/unknown/stale charge PASS")
