#!/bin/sh
# Host tests the generic inference engine without changing the N1 firewall.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
SRC="$ROOT/root/usr/libexec/tvguard-shadow"
DST="$TMP/tvguard-shadow"
CSV="$TMP/calibration-v3.csv"

python3 - "$SRC" "$DST" "$CSV" <<'PY'
from pathlib import Path
import sys
src,dst,path=sys.argv[1:]
s=Path(src).read_text()
anchor='DATA=/usr/libexec/tvguard-data\nDIR="$("$DATA" root)"\nCSV="$DIR/calibration-v3.csv"'
assert anchor in s
Path(dst).write_text(s.replace(anchor,"CSV="+path,1))

# Generic model is trained on two representative apps, not every app.
# Every window has unique session ID; each state has 6 independent sessions.
rows=[]
scenes={"playing":(180,30,150,65000),
        "paused":(85,5,80,30000),
        "app_home":(30,1,28,16000)}
sid=0
for app in ("tencent","iqiyi"):
    for scene,base in scenes.items():
        for session in range(3):
            sid+=1
            for window in range(8):
                p,t,u,b=base
                vals=(p+window%2,t+window%2,u+window%2,b+window*20)
                rows.append(f"{1730000000+sid*120+window*10},{sid}-1,{scene},{app}," +
                            ",".join(map(str,vals)))
for session in range(3):
    sid+=1
    for window in range(8):
        rows.append(f"{1730000000+sid*120+window*10},{sid}-1,system_home,system,8,1,7,2800")
Path(path).write_text("\n".join(rows)+"\n")
PY

# No App is provided at prediction time: the output is universal.
test "$(sh "$DST" 180 30 150 65000)" = 'playing general 100'
test "$(sh "$DST" 85 5 80 30000)" = 'idle general 100'
test "$(sh "$DST" 30 1 28 16000)" = 'idle general 100'
test "$(sh "$DST" 8 1 7 2800)" = 'idle general 95'
test "$(sh "$DST" 5000 10 4990 9000000)" = 'unknown none 0'
test "$(sh "$DST" 0 0 0 0)" = 'unknown none 0'

# Real-N1 shaped regression: system home has 3 sessions / 24 samples,
# while playback has only one labelled session / 11 samples. This should be
# enough for system-home because playback is only a negative overlap reference.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
sid=100
for session in range(3):
    sid += 1
    for i in range(8):
        rows.append(f"{1730100000+sid*120+i*10},{sid}-1,system_home,system,{8+i%2},1,{7+i%2},{2800+i*20}")
sid += 1
for i in range(11):
    rows.append(f"{1730200000+sid*120+i*10},{sid}-1,playing,tencent,{180+i%2},{30+i%2},{150+i%2},{65000+i*20}")
p.write_text("\n".join(rows)+"\n")
PY
test "$(sh "$DST" 9 1 8 3000)" = 'system_home system 100'
test "$(sh "$DST" 180 30 150 65000)" != 'system_home system 100'

# With fewer than 2 different video applications, generic IDLE inference
# stays off. Informational playing may still use a clearly separated local
# playback reference because it never grants free time.
grep -v ',iqiyi,' "$CSV" > "$TMP/oneapp.csv"
mv "$TMP/oneapp.csv" "$CSV"
test "$(sh "$DST" 180 30 150 65000)" = 'playing general 95'
test "$(sh "$DST" 8 1 7 2800)" = 'system_home system 100'

# A second app restored but pause evidence is still missing. Generic idle
# remains unavailable, while the explicitly labelled App-home envelope may
# use the device-local fallback.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=p.read_text().splitlines()
rows += [
    f"{1730000100+session*120+i*10},{900+session}-1,playing,iqiyi,180,30,150,65000"
    for session in range(3) for i in range(8)
]
rows += [
    f"{1730001100+session*120+i*10},{910+session}-1,app_home,iqiyi,30,1,28,16000"
    for session in range(3) for i in range(8)
]
p.write_text("\n".join(rows)+"\n")
PY
test "$(sh "$DST" 30 1 28 16000)" = 'idle general 90'

# Complete cross-app evidence, but overlapping pause/play windows must not
# become a seemingly confident playback or pause hint.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
sid=1
for app in ("tencent","iqiyi"):
    for scene,vals in {
        "playing":(100,2,97,50000),
        "paused":(100,2,97,50000),
        "app_home":(25,1,23,12000)
    }.items():
        for repeat in range(3):
            sid+=1
            for i in range(8):
                rows.append(f"{1730000000+sid*120+i*10},{sid}-1,{scene},{app}," +
                            ",".join(map(str,vals)))
p.write_text("\n".join(rows)+"\n")
PY
test "$(sh "$DST" 100 2 97 50000)" = 'unknown none 0'
test "$(sh "$DST" 25 1 23 12000)" = 'idle general 100'

# Real-N1 shaped local App-home evidence: one labelled 12-window session,
# plus one playback reference session, is enough to exempt only matching
# App-home-like traffic. Playback remains non-idle.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
sid=300
for i in range(11):
    rows.append(f"{1730300000+sid*120+i*10},{sid}-1,playing,tencent,{180+i%2},{5+i%2},{174+i%2},{55000+i*20}")
sid += 1
for i in range(12):
    rows.append(f"{1730400000+sid*120+i*10},{sid}-1,app_home,tencent,{30+i%2},{1+i%2},{28+i%2},{24000+i*20}")
p.write_text("\n".join(rows)+"\n")
PY
test "$(sh "$DST" 30 1 28 24000)" = 'app_home general 90'
test "$(sh "$DST" 180 5 174 55000)" != 'app_home general 90'

# If a point sits in both verified idle envelopes, do not lie about the exact
# foreground screen. Neutral idle is still safe for billing.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=p.read_text().splitlines()
# Extend the local App-home envelope down to the real N1 boundary seen in
# field data (about 14 PPS) while preserving the original 30-PPS samples.
sid=390
for i in range(12):
    rows.append(f"{1730450000+sid*120+i*10},{sid}-1,app_home,tencent,{14+i%2},{i%2},{13+i%2},{7000+i*20}")
sid=400
for session in range(3):
    sid += 1
    for i in range(8):
        rows.append(f"{1730500000+sid*120+i*10},{sid}-1,system_home,system,{10+i%2},1,{9+i%2},{7000+i*20}")
p.write_text("\n".join(rows)+"\n")
PY
test "$(sh "$DST" 13 1 13 7055)" = 'idle general 95'

# N1 launcher drift regression: while still on system home, one secondary
# dimension may spike (TCP or bytes) without turning the sample into unknown.
# PPS must remain in the calibrated low-activity home band, and playback-like
# PPS must still be rejected.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
sid=500
for session in range(3):
    sid += 1
    for i in range(8):
        # Mirrors the observed launcher baseline around 7-12 PPS.
        rows.append(f"{1730600000+sid*120+i*10},{sid}-1,system_home,system,{7+i%6},{4+i%5},{3+i%6},{3000+i*80}")
sid += 1
for i in range(11):
    rows.append(f"{1730700000+sid*120+i*10},{sid}-1,playing,tencent,{91+i*20},{1+i%4},{80+i*20},{50000+i*2000}")
p.write_text("\n".join(rows)+"\n")
PY
# TCP burst: PPS/UDP/bytes still home-like.
test "$(sh "$DST" 16 12 4 4004)" = 'system_home system 100'
# Byte burst: PPS/TCP/UDP still home-like.
test "$(sh "$DST" 11 7 3 45852)" = 'system_home system 100'
# Playback-level PPS can never use the launcher exception.
test "$(sh "$DST" 98 1 96 99364)" != 'system_home system 100'

# N1 playback display regression: ambiguous playback/pause overlap stays
# unknown, while a burst clearly above all pause/home ceilings may be labelled
# playing. Both states remain billable either way.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
sid=600
# One labelled playback session: 91-309 PPS.
for i in range(11):
    pps=91+i*21
    rows.append(f"{1730800000+sid*120+i*10},{sid}-1,playing,tencent,{pps},{1+i%4},{max(1,pps-3)},{35000+i*2500}")
sid += 1
# One pause reference session overlapping the lower playback range: 65-157.
for i in range(12):
    pps=65+i*8
    rows.append(f"{1730900000+sid*120+i*10},{sid}-1,paused,tencent,{pps},{1+i%3},{max(1,pps-4)},{26000+i*900}")
sid += 1
# One App-home session, 14-71.
for i in range(12):
    pps=14+i*5
    rows.append(f"{1731000000+sid*120+i*10},{sid}-1,app_home,tencent,{pps},{i%2},{max(1,pps-2)},{8000+i*600}")
# Repeated system-home evidence.
for session in range(3):
    sid += 1
    for i in range(8):
        rows.append(f"{1731100000+sid*120+i*10},{sid}-1,system_home,system,{7+i%6},{i%2},{6+i%5},{3000+i*100}")
p.write_text("\n".join(rows)+"\n")
PY
# 144 PPS still overlaps the labelled pause range: do not pretend certainty.
test "$(sh "$DST" 144 2 141 35441)" = 'unknown none 0'
# 405 PPS is clearly beyond all local idle/pause references.
test "$(sh "$DST" 405 79 326 48857)" = 'playing general 95'

echo 'PASS: system-home idle, cross-app generic idle, overlap rejection, unknown sleep'
