#!/usr/bin/env python3
"""Exercise v0.2.9 generic learned-context temporal fusion with real shell code."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-fusion").read_text()

APP_A = "com.example.videoa"
PLAYER_A = "com.example.videoa.ui.RootTaskActivity"
BROWSE_A = "com.example.videoa.ui.BrowseActivity"
APP_B = "com.example.videob"
PLAYER_B = "com.example.videob.ui.WatchScreen"

with tempfile.TemporaryDirectory(prefix="tvguard-fusion-") as folder:
    d = Path(folder)
    data = d / "tvguard-data"
    data.write_text("#!/bin/sh\n[ \"$1\" = root ] && printf '%s\\n' \"$(dirname \"$0\")\"\n")
    data.chmod(0o755)
    script = source.replace("RAM=/var/run/tvguard-agent-bridge", f"RAM={d}")
    script = script.replace("DATA=/usr/libexec/tvguard-data", f"DATA={data}")
    target = d / "fusion"
    target.write_text(script)
    target.chmod(0o755)

    def write_audio_profile(pkg=APP_A, activity=PLAYER_A,
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

    def write_nonplaying_profile(pkg=APP_A, activity=PLAYER_A,
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

    def reset():
        for name in ("fusion.state", "fusion.lock"):
            p = d / name
            if p.is_file():
                p.unlink()
            elif p.is_dir():
                p.rmdir()

    def run(seq, seen, pkg=APP_A, activity=PLAYER_A, audio=1, screen=1,
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

    # Platform launcher remains a directly observable system-home signal.
    reset()
    assert run(1, 100, pkg="com.mitv.tvhome",
               activity="com.mitv.tvhome.MainActivityUserMode",
               pause_hint="none", pause_score=0)[:2] == (
        "system_home", "system_home_confirmed")

    # An arbitrary app/package name is NOT special-cased. It becomes a learned
    # media context only after strong current playback evidence.
    reset()
    assert run(1, 200, pkg=APP_A, activity=PLAYER_A,
               pps=160, shadow="unknown",
               adaptive_state="active", adaptive_score=100,
               adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "playing", "playing_confirmed_context_learned", 0)

    # Human-labelled paired sessions teach exact-context audio semantics.
    # Low-bitrate audio-active playback must charge/play even below the network
    # floor. Two fresh audio-off reports confirm pause and the latched pause
    # must survive a high-PPS burst.
    reset()
    write_audio_profile()
    assert run(1, 300, pkg=APP_A, activity=PLAYER_A, audio=1,
               pps=8, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low",
               pause_hint="idle_overlap", pause_score=60,
               active_floor=100) == (
        "playing", "playing_confirmed_learned_audio_profile", 0)
    assert run(2, 310, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "unknown", "paused_audio_profile_warming", 1)
    assert run(3, 320, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "paused", "paused_confirmed_learned_audio_context", 2)
    assert run(4, 330, pkg=APP_A, activity=PLAYER_A, audio=1,
               pps=5, shadow="idle", adaptive_state="ambiguous",
               adaptive_score=50, adaptive_reason="overlap",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "playing", "playing_confirmed_learned_audio_profile", 0)

    # Three high-quality human-labelled states in the SAME exact context teach
    # Type-D playing vs generic nonplaying semantics. The runtime must not lie
    # by calling audio-off "paused" or "app_home" when both share that context.
    reset()
    write_nonplaying_profile()
    assert run(1, 350, pkg=APP_A, activity=PLAYER_A, audio=1,
               pps=6, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low",
               pause_hint="idle_overlap", pause_score=60,
               active_floor=100) == (
        "playing", "playing_confirmed_learned_nonplaying_profile", 0)
    assert run(2, 360, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "unknown", "nonplaying_audio_profile_warming", 1)
    # Re-reading the same report never manufactures the second vote.
    assert run(2, 360, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "unknown", "nonplaying_audio_profile_warming", 1)
    assert run(3, 370, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "nonplaying", "nonplaying_confirmed_learned_audio_context", 2)
    assert run(4, 380, pkg=APP_A, activity=PLAYER_A, audio=1,
               pps=5, shadow="idle", adaptive_state="ambiguous",
               adaptive_score=50, adaptive_reason="overlap",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "playing", "playing_confirmed_learned_nonplaying_profile", 0)

    # Type-D authority requires BOTH free-state labels. A same-context home
    # sample with audio still active is a conflict, not permission to free time.
    reset()
    write_nonplaying_profile(home_audio=80)
    assert run(1, 390, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "playing", "playing_confirmed_context_learned", 0)

    # Without strong playing-vs-paused audio separation, the model has no
    # authority and the conservative legacy path remains in force.
    reset()
    write_audio_profile(play_audio=55, pause_audio=20)
    assert run(1, 400, pkg=APP_A, activity=PLAYER_A, audio=0,
               pps=300, shadow="playing", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "playing", "playing_confirmed_context_learned", 0)

    # Return to the legacy no-profile scenario with a clean chronological
    # timeline; the profile-specific tests above must not leak state/model.
    (d / "learning-sessions.csv").unlink()
    reset()
    assert run(1, 200, pkg=APP_A, activity=PLAYER_A,
               pps=160, shadow="unknown",
               adaptive_state="active", adaptive_score=100,
               adaptive_reason="clear_current",
               pause_hint="none", pause_score=0,
               active_floor=100) == (
        "playing", "playing_confirmed_context_learned", 0)

    # The same learned context may enter pause only after three NEW strong
    # pause-hint reports. Activity name contains no Player/Video keyword.
    # A fresh strong-play sample gets a short bootstrap guard so bursty
    # low-bitrate valleys cannot immediately become pause. After the guard
    # expires, genuine sustained pause evidence can still confirm.
    assert run(2, 220, pkg=APP_A, activity=PLAYER_A) == (
        "unknown", "recent_play_burst_guard", 0)
    assert run(3, 250, pkg=APP_A, activity=PLAYER_A) == (
        "unknown", "pause_candidate_learned_context", 1)
    assert run(4, 260, pkg=APP_A, activity=PLAYER_A) == (
        "unknown", "pause_candidate_learned_context", 2)
    assert run(5, 270, pkg=APP_A, activity=PLAYER_A) == (
        "paused", "paused_confirmed_learned_context", 3)

    # Duplicate reads cannot manufacture another temporal vote.
    assert run(5, 270, pkg=APP_A, activity=PLAYER_A) == (
        "paused", "paused_confirmed_learned_context", 3)

    # One missing hint is held; a second releases pause.
    assert run(6, 280, pkg=APP_A, activity=PLAYER_A,
               pause_hint="none", pause_score=0) == (
        "paused", "paused_temporal_hold", 3)
    assert run(7, 290, pkg=APP_A, activity=PLAYER_A,
               pause_hint="none", pause_score=0) == (
        "unknown", "learned_media_context_unresolved", 0)

    # Explicit playback evidence exits pause immediately and refreshes the
    # learned context.
    run(8, 310, pkg=APP_A, activity=PLAYER_A,
        pause_hint="bursty_pause", pause_score=75)
    run(9, 320, pkg=APP_A, activity=PLAYER_A,
        pause_hint="bursty_pause", pause_score=75)
    assert run(10, 330, pkg=APP_A, activity=PLAYER_A,
               pps=180, shadow="unknown",
               adaptive_state="active", adaptive_score=100,
               adaptive_reason="clear_current",
               pause_hint="high_ratio_pause", pause_score=95,
               active_floor=100) == (
        "playing", "playing_confirmed_context_learned", 0)

    # P0 guard: low-rate playback in a learned media context can remain
    # idle_overlap forever without becoming paused.
    reset()
    run(1, 300, pkg=APP_B, activity=PLAYER_B,
        pps=180, shadow="unknown", adaptive_state="active",
        adaptive_score=100, adaptive_reason="clear_current",
        pause_hint="none", pause_score=0, active_floor=100)
    for i, pps in enumerate((9, 12, 8, 11, 10, 14, 7), 2):
        state, candidate, streak = run(
            i, 350 + i * 10, pkg=APP_B, activity=PLAYER_B,
            audio=1, pps=pps, shadow="idle",
            adaptive_state="idle", adaptive_score=95,
            adaptive_reason="stable_low",
            pause_hint="idle_overlap", pause_score=60,
            active_floor=100)
        assert state == "unknown", (i, state, candidate, streak)
        assert candidate == "learned_media_idle_overlap_unresolved"
        assert streak == 0

    # Generic app-side non-playing state: after playback taught APP_A as a media
    # package, another Activity with sustained low/no-audio evidence becomes
    # app_home. This means "app-side non-playing UI", not a package-specific root.
    reset()
    run(1, 500, pkg=APP_A, activity=PLAYER_A,
        pps=160, shadow="unknown", adaptive_state="active",
        adaptive_score=100, adaptive_reason="clear_current",
        pause_hint="none", pause_score=0, active_floor=100)
    assert run(2, 510, pkg=APP_A, activity=BROWSE_A, audio=0, pps=8,
               shadow="idle", adaptive_state="idle", adaptive_score=95,
               adaptive_reason="stable_low", pause_hint="idle_overlap",
               pause_score=60, active_floor=100) == (
        "unknown", "app_nonplaying_warming", 0)
    assert run(3, 520, pkg=APP_A, activity=BROWSE_A, audio=0, pps=7,
               shadow="idle", adaptive_state="idle", adaptive_score=95,
               adaptive_reason="stable_low", pause_hint="idle_overlap",
               pause_score=60, active_floor=100) == (
        "unknown", "app_nonplaying_warming", 0)
    assert run(4, 530, pkg=APP_A, activity=BROWSE_A, audio=0, pps=6,
               shadow="idle", adaptive_state="idle", adaptive_score=95,
               adaptive_reason="stable_low", pause_hint="idle_overlap",
               pause_score=60, active_floor=100) == (
        "app_home", "app_nonplaying_confirmed", 0)

    # Regression: a loading burst in another Activity of an already learned
    # media package must NOT overwrite the learned player Activity. This is the
    # real failure mode that made an app home page impossible to recognize.
    reset()
    run(1, 600, pkg=APP_A, activity=PLAYER_A,
        pps=180, shadow="unknown", adaptive_state="active",
        adaptive_score=100, adaptive_reason="clear_current",
        pause_hint="none", pause_score=0, active_floor=100)
    assert run(2, 610, pkg=APP_A, activity=BROWSE_A, audio=0,
               pps=180, shadow="unknown", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0, active_floor=100) == (
        "unknown", "media_context_switch_play_warming", 0)
    state_fields = (d / "fusion.state").read_text().strip().split("|")
    assert state_fields[0] == "4", state_fields
    assert state_fields[6] == APP_A, state_fields
    assert state_fields[7] == PLAYER_A, state_fields
    for seq, seen, pps in ((3, 620, 11), (4, 630, 9)):
        assert run(seq, seen, pkg=APP_A, activity=BROWSE_A, audio=0,
                   pps=pps, shadow="idle", adaptive_state="idle",
                   adaptive_score=95, adaptive_reason="stable_low",
                   pause_hint="idle_overlap", pause_score=60,
                   active_floor=100) == (
            "unknown", "app_nonplaying_warming", 0)
    assert run(5, 640, pkg=APP_A, activity=BROWSE_A, audio=0,
               pps=8, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low",
               pause_hint="idle_overlap", pause_score=60,
               active_floor=100) == (
        "app_home", "app_nonplaying_confirmed", 0)

    # A genuinely new playback Activity can still replace the old one, but only
    # after three fresh strong-play confirmations in the same context.
    reset()
    run(1, 700, pkg=APP_A, activity=PLAYER_A,
        pps=180, shadow="unknown", adaptive_state="active",
        adaptive_score=100, adaptive_reason="clear_current",
        pause_hint="none", pause_score=0, active_floor=100)
    for seq, seen in ((2, 710), (3, 720)):
        assert run(seq, seen, pkg=APP_A, activity=BROWSE_A, audio=1,
                   pps=180, shadow="unknown", adaptive_state="active",
                   adaptive_score=100, adaptive_reason="clear_current",
                   pause_hint="none", pause_score=0, active_floor=100) == (
            "unknown", "media_context_switch_play_warming", 0)
    assert run(4, 730, pkg=APP_A, activity=BROWSE_A, audio=1,
               pps=180, shadow="unknown", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0, active_floor=100) == (
        "playing", "playing_confirmed_context_switched", 0)

    # A never-learned package cannot claim app_home or pause from network hints.
    reset()
    for i in range(1, 5):
        state, candidate, streak = run(
            i, 600 + i * 10, pkg="com.example.unknown",
            activity="com.example.unknown.HomeActivity",
            audio=0, pps=5, shadow="idle",
            adaptive_state="idle", adaptive_score=95,
            adaptive_reason="stable_low",
            pause_hint="high_ratio_pause", pause_score=95)
        assert state == "unknown"
        assert candidate == "unlearned_package_pause_hint_ignored"
        assert streak == 0

    # Agent restart clears hysteresis but preserves N1-learned context. First
    # post-restart report is recovery only and does not vote pause/home.
    reset()
    run(30, 700, pkg=APP_A, activity=PLAYER_A,
        pps=160, shadow="unknown", adaptive_state="active",
        adaptive_score=100, adaptive_reason="clear_current",
        pause_hint="none", pause_score=0, active_floor=100)
    run(31, 760, pkg=APP_A, activity=PLAYER_A)
    run(32, 770, pkg=APP_A, activity=PLAYER_A)
    assert run(33, 780, pkg=APP_A, activity=PLAYER_A)[0] == "paused"
    assert run(1, 790, pkg=APP_A, activity=PLAYER_A) == (
        "unknown", "agent_process_restart_context_reset", 0)

    # Incomplete foreground can improve only positive playback direction.
    reset()
    assert run(1, 900, pkg="unknown", activity="unknown", audio=1,
               pps=180, shadow="unknown", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0, active_floor=100) == (
        "playing", "playing_network_audio_fallback", 0)
    assert run(2, 910, pkg=APP_A, activity="unknown", audio=1,
               pps=180, shadow="unknown", adaptive_state="active",
               adaptive_score=100, adaptive_reason="clear_current",
               pause_hint="none", pause_score=0, active_floor=100) == (
        "playing", "playing_package_only_fallback", 0)
    reset()
    assert run(1, 920, pkg="com.mitv.tvhome", activity="unknown", audio=0,
               pps=5, shadow="idle", adaptive_state="idle",
               adaptive_score=95, adaptive_reason="stable_low",
               pause_hint="high_ratio_pause", pause_score=95) == (
        "unknown", "launcher_context_incomplete", 0)

    # Package-only gaps preserve the last exact context but clear free latches.
    reset()
    run(10, 1000, pkg=APP_A, activity=PLAYER_A, audio=1,
        pps=180, shadow="unknown", adaptive_state="active",
        adaptive_score=100, adaptive_reason="clear_current",
        pause_hint="none", pause_score=0, active_floor=100)
    assert run(11, 1010, pkg=APP_A, activity="unknown", audio=0, pps=5,
               shadow="idle", adaptive_state="idle", adaptive_score=95,
               adaptive_reason="stable_low", pause_hint="high_ratio_pause",
               pause_score=95, active_floor=100) == (
        "unknown", "package_only_context_unresolved", 0)
    saved=(d / "fusion.state").read_text().strip().split("|")
    assert saved[9] == APP_A and saved[10] == PLAYER_A, saved

print("v0.2.9 generic fusion: exact-context free states + safe incomplete-context playback fallback PASS")
