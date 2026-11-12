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
V5="$TMP/state/calibration-v5.csv"
: > "$CSV"
: > "$V5"
i=0
while [ "$i" -lt 18 ]; do
    ts=$((1700000000 + i*10))
    p=$((8 + i%5))
    tcp=$((i%3))
    udp=$((p-tcp))
    b=$((3000 + i*100))
    printf '%s,1700000000-1,system_home,system,%s,%s,%s,%s\n' \
        "$ts" "$p" "$tcp" "$udp" "$b" >> "$CSV"
    audio=0
    [ "$i" -eq 17 ] && audio=1
    printf '%s,1700000000-1,system_home,fresh,2,com.mitv.tvhome,com.mitv.tvhome.MainActivityUserMode,%s,1,%s,%s,%s,%s,%s\n' \
        "$ts" "$audio" "$((100+i))" "$p" "$tcp" "$udp" "$b" >> "$V5"
    i=$((i + 1))
done

sh "$DST" 1700000000-1 system_home 180 system completed 1700000180
REPORT="$TMP/state/learning-last.txt"
grep -q '^状态: 电视系统首页$' "$REPORT"
grep -q '^样本完整度: 100% · 高$' "$REPORT"
grep -q '^PPS: P10 ' "$REPORT"
grep -q '^Agent 传输: 18/18 fresh · 覆盖 100%
grep -q '^应用包上下文: 18/18 · 覆盖 100% · com.mitv.tvhome · 稳定 100%
grep -q '^完整前台上下文: 18/18 · 覆盖 100% · com.mitv.tvhome.MainActivityUserMode · 稳定 100%
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"


# Fresh transport with unknown/unknown foreground must never be high-confidence.
sid=1794475000-999
: > "$V5"
: > "$CSV"
i=0
while [ "$i" -lt 12 ]; do
    ts=$((1794475000 + i * 10))
    printf '%s,%s,playing,general,80,1,79,20000\n' "$ts" "$sid" >> "$CSV"
    printf '%s,%s,playing,fresh,1,unknown,unknown,1,1,%s,80,1,79,20000,allowed,none,no_foreground,unknown\n' \
        "$ts" "$sid" "$i" >> "$V5"
    i=$((i + 1))
done
sh "$DST" "$sid" playing 120 general completed 1794475120
REPORT="$TMP/state/learning-last.txt"
grep -q '^Agent 传输: 12/12 fresh · 覆盖 100%
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^应用包上下文: 0/12 · 覆盖 0% · unknown · 稳定 0%
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^完整前台上下文: 0/12 · 覆盖 0% · unknown · 稳定 0%
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^联合质量: network_only
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"

echo 'PASS: learning session analysis + unknown-context quality gate'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
 "$REPORT"
grep -q '^自动应用: com.mitv.tvhome · 稳定 100%$' "$REPORT"
grep -q '^主要页面: com.mitv.tvhome.MainActivityUserMode · 稳定 100%$' "$REPORT"
grep -q '^电视上下文: 音频活跃 5% · 屏幕亮 100% · 前台切换 0 次$' "$REPORT"
grep -q '^联合质量: high$' "$REPORT"
awk -F, 'NF==18 && $2=="1700000000-1" && $3=="system_home" && $9==100 && $18=="high" {ok=1} END {exit !ok}' \
    "$TMP/state/learning-sessions.csv"

echo 'PASS: learning session analysis produces network + Agent context statistics'
