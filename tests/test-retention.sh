#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/state"

cat > "$TMP/data" <<'SH'
#!/bin/sh
case "${1:-root}" in
    root|persistent-root) printf '%s\n' "$TVG_RETENTION_STATE" ;;
    status) printf 'persistent|%s|mounted\n' "$TVG_RETENTION_STATE" ;;
    *) exit 2 ;;
esac
SH
chmod +x "$TMP/data"
export TVG_RETENTION_STATE="$TMP/state"

SRC="$ROOT/root/usr/libexec/tvguard-retention"
DST="$TMP/retention"
python3 - "$SRC" "$DST" "$TMP/data" <<'PY'
from pathlib import Path
import sys
src,dst,data=sys.argv[1:]
s=Path(src).read_text()
anchor='DATA=/usr/libexec/tvguard-data'
assert anchor in s
s=s.replace(anchor,'DATA='+data,1)
Path(dst).write_text(s)
PY
chmod +x "$DST"

make_lines() {
    file="$1"
    count="$2"
    payload="$3"
    : > "$file"
    i=1
    while [ "$i" -le "$count" ]; do
        printf '%06d,%s\n' "$i" "$payload" >> "$file"
        i=$((i + 1))
    done
}

make_lines "$TMP/state/events.log" 5000 "event-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
make_lines "$TMP/state/calibration-v3.csv" 5000 "v3-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
make_lines "$TMP/state/calibration-v4.csv" 6000 "v4-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
make_lines "$TMP/state/learning-sessions.csv" 3000 "session-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

sh "$DST" trim

[ "$(wc -l < "$TMP/state/events.log")" -le 1500 ]
[ "$(wc -l < "$TMP/state/calibration-v3.csv")" -le 1500 ]
[ "$(wc -l < "$TMP/state/calibration-v4.csv")" -le 1800 ]
[ "$(wc -l < "$TMP/state/learning-sessions.csv")" -le 512 ]
[ "$(wc -c < "$TMP/state/events.log")" -le 262144 ]
[ "$(wc -c < "$TMP/state/calibration-v3.csv")" -le 262144 ]
[ "$(wc -c < "$TMP/state/calibration-v4.csv")" -le 393216 ]
[ "$(wc -c < "$TMP/state/learning-sessions.csv")" -le 131072 ]

grep -q '^005000,' "$TMP/state/events.log"
grep -q '^005000,' "$TMP/state/calibration-v3.csv"
grep -q '^006000,' "$TMP/state/calibration-v4.csv"
grep -q '^003000,' "$TMP/state/learning-sessions.csv"

report="$(sh "$DST" report)"
printf '%s\n' "$report" | grep -q '^数据模式: persistent$'
printf '%s\n' "$report" | grep -q "^当前数据目录: $TMP/state$"
printf '%s\n' "$report" | grep -q "^持久目录: $TMP/state$"
printf '%s\n' "$report" | grep -q '^状态: mounted$'
printf '%s\n' "$report" | grep -q '持久追加预算: 1048576 bytes (1 MiB)'
printf '%s\n' "$report" | grep -q 'Adaptive 滚动窗口: /var/run/tvguard-adaptive-window.csv'

echo 'PASS: persistent append-only TV Guard data is hard-bounded to a 1 MiB design budget'
