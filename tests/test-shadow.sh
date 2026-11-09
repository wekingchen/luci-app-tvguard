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
anchor="CSV=/etc/tvguard/calibration-v3.csv"
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
test "$(sh "$DST" 8 1 7 2800)" = 'system_home system 100'
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

# With fewer than 2 different video applications, generic app-idle inference stays off;
# repeated device-level system-home evidence may still be recognized safely.
grep -v ',iqiyi,' "$CSV" > "$TMP/oneapp.csv"
mv "$TMP/oneapp.csv" "$CSV"
test "$(sh "$DST" 180 30 150 65000)" = 'unknown none 0'
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
test "$(sh "$DST" 30 1 28 16000)" = 'app_home general 90'

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

echo 'PASS: system-home idle, cross-app generic idle, overlap rejection, unknown sleep'
