#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/persist" "$TMP/run"

cat > "$TMP/data" <<'SH'
#!/bin/sh
case "$1" in
    root|persistent-root) printf '%s\n' "$TVG_SOAK_PERSIST" ;;
    status) printf 'persistent|%s|mounted\n' "$TVG_SOAK_PERSIST" ;;
    *) exit 2 ;;
esac
SH
chmod +x "$TMP/data"
export TVG_SOAK_PERSIST="$TMP/persist"

SRC="$ROOT/root/usr/libexec/tvguard-soak"
DST="$TMP/soak"
python3 - "$SRC" "$DST" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
s=Path(src).read_text()
s=s.replace('DATA=/usr/libexec/tvguard-data','DATA='+tmp+'/data',1)
s=s.replace('RING=/var/run/tvguard-soak-window.csv','RING='+tmp+'/run/ring.csv',1)
s=s.replace('STATE=/var/run/tvguard-soak.state','STATE='+tmp+'/run/state',1)
s=s.replace('SCHEMA_FILE=/var/run/tvguard-soak-schema','SCHEMA_FILE='+tmp+'/run/schema',1)
Path(dst).write_text(s)
PY
chmod +x "$DST"

run() { sh "$DST" "$@"; }

out="$(run 1000 parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing)"
echo "$out" | grep -q '^none '

out="$(run 1010 parent active 95 high_ratio_pause 95 120 2 116 210000 118 190 1700 2500 3 20 unknown)"
echo "$out" | grep -q '^enter 0 1 0 '
run 1020 parent active 95 high_ratio_pause 95 110 1 108 220000 115 180 1800 2600 2 10 unknown >/dev/null
run 1030 parent ambiguous 50 high_ratio_pause 95 100 0 98 230000 105 170 1900 2700 0 5 unknown >/dev/null

out="$(run 1040 parent active 100 none 0 180 30 145 300000 150 240 4000 5200 4 -30 playing)"
echo "$out" | grep -q '^exit 30 1 1 30 30 '
grep -q '^HIGH_RATIO_ENTERS=1$' "$TMP/persist/soak-summary"
grep -q '^HIGH_RATIO_EXITS=1$' "$TMP/persist/soak-summary"
grep -q '^MAX_HIGH_RATIO_SECONDS=30

sed -i 's/MAX_LINES=2160/MAX_LINES=5/; s/TRIM_AT=2200/TRIM_AT=7/' "$DST"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1100+i*10))" parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing >/dev/null
done
[ "$(wc -l < "$TMP/run/ring.csv")" -le 7 ]
[ "$(wc -c < "$TMP/persist/soak-summary")" -lt 4096 ]

echo 'PASS: Shadow Soak uses volatile bounded raw ring and transition/checkpoint summary only'
 "$TMP/persist/soak-summary"
grep -q '^LAST_SESSION_TCP_SUM=3

sed -i 's/MAX_LINES=2160/MAX_LINES=5/; s/TRIM_AT=2200/TRIM_AT=7/' "$DST"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1100+i*10))" parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing >/dev/null
done
[ "$(wc -l < "$TMP/run/ring.csv")" -le 7 ]
[ "$(wc -c < "$TMP/persist/soak-summary")" -lt 4096 ]

echo 'PASS: Shadow Soak uses volatile bounded raw ring and transition/checkpoint summary only'
 "$TMP/persist/soak-summary"
grep -q '^LAST_SESSION_UDP_SUM=322

sed -i 's/MAX_LINES=2160/MAX_LINES=5/; s/TRIM_AT=2200/TRIM_AT=7/' "$DST"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1100+i*10))" parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing >/dev/null
done
[ "$(wc -l < "$TMP/run/ring.csv")" -le 7 ]
[ "$(wc -c < "$TMP/persist/soak-summary")" -lt 4096 ]

echo 'PASS: Shadow Soak uses volatile bounded raw ring and transition/checkpoint summary only'
 "$TMP/persist/soak-summary"
grep -q '^LAST_SESSION_BPS_SUM=660000

sed -i 's/MAX_LINES=2160/MAX_LINES=5/; s/TRIM_AT=2200/TRIM_AT=7/' "$DST"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1100+i*10))" parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing >/dev/null
done
[ "$(wc -l < "$TMP/run/ring.csv")" -le 7 ]
[ "$(wc -c < "$TMP/persist/soak-summary")" -lt 4096 ]

echo 'PASS: Shadow Soak uses volatile bounded raw ring and transition/checkpoint summary only'
 "$TMP/persist/soak-summary"

sed -i 's/MAX_LINES=2160/MAX_LINES=5/; s/TRIM_AT=2200/TRIM_AT=7/' "$DST"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1100+i*10))" parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing >/dev/null
done
[ "$(wc -l < "$TMP/run/ring.csv")" -le 7 ]
[ "$(wc -c < "$TMP/persist/soak-summary")" -lt 4096 ]

echo 'PASS: Shadow Soak uses volatile bounded raw ring and transition/checkpoint summary only'
