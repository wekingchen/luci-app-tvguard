#!/usr/bin/env python3
"""Lock the 2026-11-11 real 576p false-pause sequence as an anonymous P0 regression."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "root/usr/libexec/tvguard-agent-fusion").read_text()

PKG = "com.example.real576"
CTX = "com.example.real576.RootTask"

# seq, epoch, pps, shadow, adaptive_state, adaptive_reason, pause_hint, pause_score
# Captured while the user explicitly labelled the TV as NORMAL 576p playback.
ROWS = [
    (42, 1000, 73,  "unknown", "active",    "active_votes", "high_ratio_pause", 95),
    (43, 1010, 346, "unknown", "active",    "clear_current", "none",             0),
    (44, 1020, 80,  "unknown", "active",    "active_votes", "high_ratio_pause", 95),
    (45, 1030, 18,  "unknown", "ambiguous", "overlap",      "high_ratio_pause", 95),
    (46, 1040, 62,  "unknown", "ambiguous", "overlap",      "high_ratio_pause", 95),
    (47, 1050, 28,  "unknown", "ambiguous", "overlap",      "none",              0),
    (48, 1060, 198, "playing", "active",    "clear_current", "none",              0),
    (49, 1070, 66,  "unknown", "ambiguous", "overlap",      "none",              0),
    (50, 1080, 20,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (51, 1090, 26,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (52, 1100, 44,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (53, 1110, 305, "unknown", "active",    "clear_current", "bursty_pause",      75),
    (54, 1120, 30,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (55, 1130, 22,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (56, 1140, 28,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (57, 1150, 125, "playing", "ambiguous", "overlap",      "bursty_pause",      75),
    (58, 1160, 19,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (59, 1170, 25,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (61, 1190, 31,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (62, 1200, 21,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (63, 1210, 174, "playing", "active",    "clear_current", "bursty_pause",      75),
    (64, 1220, 174, "playing", "active",    "clear_current", "bursty_pause",      75),
    (65, 1230, 108, "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (66, 1240, 46,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (67, 1250, 20,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (68, 1260, 40,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (69, 1270, 180, "playing", "active",    "clear_current", "bursty_pause",      75),
    (70, 1280, 25,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (71, 1290, 20,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (72, 1300, 69,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (73, 1310, 22,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (74, 1320, 220, "unknown", "active",    "clear_current", "bursty_pause",      75),
    (75, 1330, 23,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (76, 1340, 31,  "unknown", "ambiguous", "overlap",      "bursty_pause",      75),
    (77, 1350, 226, "unknown", "active",    "clear_current", "bursty_pause",      75),
]

with tempfile.TemporaryDirectory(prefix="tvguard-real576-") as folder:
    d = Path(folder)
    target = d / "fusion"
    target.write_text(source.replace("RAM=/var/run/tvguard-agent-bridge", f"RAM={d}"))
    target.chmod(0o755)

    saw_guard = False
    saw_playing = False
    for seq, epoch, pps, shadow, ast, reason, hint, score in ROWS:
        args = [
            "dash", str(target), str(epoch), str(epoch), str(seq),
            PKG, CTX, "1", "1", str(pps), shadow, ast, "95",
            reason, hint, str(score), "138",
        ]
        state, candidate, streak = subprocess.check_output(
            args, text=True).strip().split()
        streak = int(streak)

        # This entire trace was manually labelled NORMAL PLAYBACK.
        assert state != "paused", (seq, pps, state, candidate, streak)
        if state == "playing":
            saw_playing = True
        if candidate == "recent_play_burst_guard":
            saw_guard = True
            assert streak == 0, (seq, candidate, streak)

    assert saw_playing
    assert saw_guard

print("real 576p normal-playback trace: no false paused under generic burst cadence PASS")
