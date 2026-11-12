#!/usr/bin/env python3
"""Formal billing: explicit homes and freshly confirmed paused may grant free time."""
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
    data = d / "tvguard-data"
    data.write_text("#!/bin/sh\n[ \"$1\" = root ] && printf '%s\\n' \"$(dirname \"$0\")\"\n")
    data.chmod(0o755)

    fusion = d / "fusion"
    fusion_text = fusion_source.replace(
        "RAM=/var/run/tvguard-agent-bridge", f"RAM={d}")
    fusion_text = fusion_text.replace(
        "DATA=/usr/libexec/tvguard-data", f"DATA={data}")
    fusion.write_text(fusion_text)
    fusion.chmod(0o755)

    def write_audio_profile(pkg=PKG, activity=PLAYER,
                            play_audio=100, pause_audio=0):
        def row(sid, label, audio):
            return ",".join(map(str, [
                1000, sid, label, "general", 120, "completed", 12, 120,
                100, 10, 20, 30, 1, 19, 10000, 20000, "stable", "high",
                "high", 100, 100, 100, pkg, 100, activity, 100,
                audio, 100, 0,
            ]))
        (d / "learning-sessions.csv").write_text(
            row("1-play", "playing", play_audio) + "\n" +
            row("2-pause", "paused", pause_audio) + "\n"
        )

    def write_nonplaying_profile(pkg=PKG, activity=PLAYER,
                                  play_audio=100, pause_audio=5, home_audio=0):
        def row(sid, label, audio):
            return ",".join(map(str, [
                1000, sid, label, "general", 180, "completed", 17, 179,
                94, 20, 50, 120, 1, 45, 90000, 150000, "variable", "high",
                "high", 100, 100, 100, pkg, 100, activity, 100,
                audio, 100, 0,
            ]))
        (d / "learning-sessions.csv").write_text(
            row("11-play", "playing", play_audio) + "\n" +
            row("12-pause", "paused", pause_audio) + "\n" +
            row("13-home", "app_home", home_audio) + "\n"
        )

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

    # Paired manual Agent learning grants a second strict pause path. One fresh
    # audio-off report remains chargeable; the second confirms pause. Even a
    # high network burst cannot override the exact learned playing/paused context.
    write_audio_profile()
    put(14, 340, PKG, PLAYER, audio=0)
    assert run(340, pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0) == (
        "charge", "unknown")
    put(15, 350, PKG, PLAYER, audio=0)
    assert run(350, pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0) == (
        "free", "paused")
    put(16, 360, PKG, PLAYER, audio=1)
    assert run(360, pps=5, shadow="idle", adaptive_state="ambiguous",
               adaptive_score=50, adaptive_reason="overlap",
               pause_hint="none", pause_score=0) == (
        "charge", "playing")
    (d / "learning-sessions.csv").unlink()

    # Shared-context Type-D profile: first audio-off report is still charged;
    # the second fresh report grants generic nonplaying free time even if the
    # network itself looks strongly active. Audio-on exits immediately.
    write_nonplaying_profile()
    put(17, 370, PKG, PLAYER, audio=0)
    assert run(370, pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0) == (
        "charge", "unknown")
    put(18, 380, PKG, PLAYER, audio=0)
    assert run(380, pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0) == (
        "free", "nonplaying")
    put(19, 390, PKG, PLAYER, audio=1)
    assert run(390, pps=5, shadow="idle", adaptive_state="ambiguous",
               adaptive_score=50, adaptive_reason="overlap",
               pause_hint="none", pause_score=0) == (
        "charge", "playing")
    (d / "learning-sessions.csv").unlink()

    # A paused state is free only after the strict learned-context Fusion
    # confirmation path has fired on three fresh reports.
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
        "free", "paused")

    # The first fresh miss after confirmation is only a temporal hold. It may
    # still display paused, but it must not inherit billing authority.
    put(24, 490, PKG, PLAYER, audio=1)
    assert run(490, pps=45, adaptive_state="ambiguous",
               adaptive_score=50, adaptive_reason="overlap",
               pause_hint="none", pause_score=0) == (
        "charge", "paused")

    # TVG2 diagnostics are accepted; incomplete context never grants free time.
    latest.write_text(
        "495|unknown|unknown|1|1|495000|25|allowed|none|no_foreground\n")
    assert run(495, pps=180, adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current") == (
        "charge", "playing")
    latest.write_text(
        "496|com.mitv.tvhome|unknown|0|1|496000|26|allowed|usage_stats|package_only\n")
    assert run(496, pps=5, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low") == (
        "charge", "unknown")

    # A launcher report older than the 20-second billing freshness gate fails closed.
    put(30, 500, "com.mitv.tvhome", "com.mitv.tvhome.MainActivityUserMode", audio=0)
    assert run(521, pps=10) == ("charge", "unknown")

print("billing hint: system/app home + confirmed pause free; pause-hold/unknown/stale charge PASS")
