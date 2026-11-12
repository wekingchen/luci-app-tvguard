#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/state"
SRC="$ROOT/root/usr/libexec/tvguard-learn"
DST="$TMP/tvguard-learn"
python3 - "$SRC" "$DST" "$TMP/state" <<'PY'
from pathlib import Path
import sys
src,dst,state=sys.argv[1:]
s=Path(src).read_text()
anchor='DATA=/usr/libexec/tvguard-data\nDIR="$("$DATA" root)"'
assert anchor in s
s=s.replace(anchor,'DIR='+state,1)
Path(dst).write_text(s)
PY
chmod +x "$DST"
CSV="$TMP/state/calibration-v3.csv"
: > "$CSV"
i=0
while [ "$i" -lt 18 ]; do
    ts=$((1700000000 + i*10))
    p=$((8 + i%5))
    tcp=$((i%3))
    udp=$((p-tcp))
    b=$((3000 + i*100))
    printf '%s,1700000000-1,system_home,system,%s,%s,%s,%s\n' "$ts" "$p" "$tcp" "$udp" "$b" >> "$CSV"
    i=$((i + 1))
done
sh "$DST" 1700000000-1 system_home 180 system completed 1700000180
grep -q '^状态: 电视系统首页$' "$TMP/state/learning-last.txt"
grep -q '^样本完整度: 100% · 高$' "$TMP/state/learning-last.txt"
grep -q '^PPS: P10 ' "$TMP/state/learning-last.txt"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' "$TMP/state/learning-sessions.csv"
echo 'PASS: learning session analysis produces compact reusable statistics'
