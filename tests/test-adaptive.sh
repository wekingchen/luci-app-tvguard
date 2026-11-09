#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/state" "$TMP/run"
SRC="$ROOT/root/usr/libexec/tvguard-adaptive"
DST="$TMP/adaptive"
python3 - "$SRC" "$DST" "$TMP/state" "$TMP/run/window.csv" <<'PY'
from pathlib import Path
import sys
src,dst,state,window=sys.argv[1:]
s=Path(src).read_text()
s=s.replace('DIR=/etc/tvguard','DIR='+state,1)
s=s.replace('WINDOW=/var/run/tvguard-adaptive-window.csv','WINDOW='+window,1)
s=s.replace('mkdir -p /var/run','mkdir -p '+str(Path(window).parent),1)
Path(dst).write_text(s)
PY
chmod +x "$DST"
cat > "$TMP/state/learning-sessions.csv" <<'EOF'
1794211178,1794211096-91,playing,general,180,stopped,8,82,44,8,18,105,10,7,4737,15493,bursty,low
1794211425,1794211242-93,playing,general,180,completed,17,174,94,138,160,233,12,143,50891,65964,variable,high
1794211713,1794211523-95,app_home,general,180,completed,18,185,100,28,41,61,0,40,37580,58416,variable,high
1794211989,1794211806-97,system_home,system,180,completed,17,174,94,9,14,34,0,13,6409,29194,bursty,high
1794212224,1794212044-99,playing,general,180,completed,17,174,94,168,402,715,134,256,47375,99570,variable,high
1794212543,1794212354-101,paused,general,180,completed,18,185,100,12,18,101,2,14,4501,16262,bursty,high
EOF

run() { sh "$DST" "$@"; }

# The user's stopped/low playing session must be ignored. Learned boundaries
# should therefore come from completed high-quality sessions: idle P90 max 61,
# active P10 min 138, yielding an idle ceiling around 70.
out="$(run 1000 12 1 10 4000)"
echo "$out" | grep -q '^warming '
echo "$out" | awk '{exit !($6==138 && $5>=66 && $5<=76)}'

# Stable home/App-home traffic with one 16-PPS wobble remains idle as a
# rolling window instead of resetting to unknown.
run 1010 9 0 8 3200 >/dev/null
run 1020 16 5 11 4238 >/dev/null
out="$(run 1030 12 2 9 3818)"
echo "$out" | grep -q '^idle '
echo "$out" | awk '{exit !($7<=41 && $8<=61)}'

# One clearly active sample flips immediately.
out="$(run 1040 160 12 143 50891)"
echo "$out" | grep -q '^active 100 '

# Reset by time gap, then sustained ~115 PPS playback is learned as active
# from the rolling median even though each frame is below active P10 138.
run 2000 110 70 40 18000 >/dev/null
run 2010 115 77 38 18109 >/dev/null
run 2020 120 75 45 19000 >/dev/null
out="$(run 2030 116 74 42 18500)"
echo "$out" | grep -Eq '^active (85|95|100) '

# A pause-like low median with a burst near 101 must not be granted idle in
# Phase 1; it remains ambiguous and therefore billable.
run 3000 12 2 10 4500 >/dev/null
run 3010 18 2 14 4600 >/dev/null
run 3020 101 3 97 16000 >/dev/null
out="$(run 3030 18 2 14 4400)"
echo "$out" | grep -q '^ambiguous '

echo 'PASS: adaptive phase1 learns dynamic boundaries and rolling-window states'
