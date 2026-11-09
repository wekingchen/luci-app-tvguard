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
for old,new in (
    ('DATA=/usr/libexec/tvguard-data','DATA='+tmp+'/data'),
    ('RING=/var/run/tvguard-soak-window.csv','RING='+tmp+'/run/ring.csv'),
    ('STATE=/var/run/tvguard-soak.state','STATE='+tmp+'/run/state'),
    ('SCHEMA_FILE=/var/run/tvguard-soak-schema','SCHEMA_FILE='+tmp+'/run/schema'),
):
    assert old in s, old
    s=s.replace(old,new,1)
Path(dst).write_text(s)
PY
chmod +x "$DST"

run() { sh "$DST" "$@"; }

# r10 -> r11 migration: old summaries have no SOAK_SCHEMA/protocol sums. v2
# must start a clean evidence epoch instead of dividing new protocol sums by
# old candidate/sample counters.
cat > "$TMP/persist/soak-summary" <<'EOF'
TOTAL_SAMPLES=132
HIGH_RATIO_SAMPLES=31
HIGH_RATIO_ENTERS=8
HIGH_RATIO_EXITS=7
HIGH_RATIO_SECONDS=239
MAX_HIGH_RATIO_SECONDS=83
LAST_HINT=high_ratio_pause
CANDIDATE_START=900
CANDIDATE_SAMPLES=8
CHECKPOINT_EPOCH=900
EOF
rm -f "$TMP/run/state"
out="$(run 1000 parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing)"
echo "$out" | grep -q '^none '
grep -qx 'SOAK_SCHEMA=v2' "$TMP/run/state"
grep -qx 'TOTAL_SAMPLES=1' "$TMP/run/state"
grep -qx 'HIGH_RATIO_SAMPLES=0' "$TMP/run/state"
grep -qx 'HIGH_RATIO_ENTERS=0' "$TMP/run/state"

# Reset the synthetic migration fixture before the main transition scenario.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"

# Normal playback: no overlap transition.
out="$(run 1000 parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing)"
echo "$out" | grep -q '^none '

# Three high-B/P windows with UDP-dominant protocol mix.
out="$(run 1010 parent active 95 high_ratio_pause 95 120 2 116 210000 118 190 1700 2500 3 20 unknown)"
echo "$out" | grep -q '^enter 0 1 0 '
run 1020 parent active 95 high_ratio_pause 95 110 1 108 220000 115 180 1800 2600 2 10 unknown >/dev/null
run 1030 parent ambiguous 50 high_ratio_pause 95 100 0 98 230000 105 170 1900 2700 0 5 unknown >/dev/null

# Exit snapshots the completed overlap session, including protocol/throughput
# evidence. These fields are observation-only.
out="$(run 1040 parent active 100 none 0 180 30 145 300000 150 240 4000 5200 4 -30 playing)"
echo "$out" | grep -q '^exit 30 1 1 30 30 '
grep -qx 'HIGH_RATIO_ENTERS=1' "$TMP/persist/soak-summary"
grep -qx 'HIGH_RATIO_EXITS=1' "$TMP/persist/soak-summary"
grep -qx 'MAX_HIGH_RATIO_SECONDS=30' "$TMP/persist/soak-summary"
grep -qx 'LAST_SESSION_TCP_SUM=3' "$TMP/persist/soak-summary"
grep -qx 'LAST_SESSION_UDP_SUM=322' "$TMP/persist/soak-summary"
grep -qx 'LAST_SESSION_BPS_SUM=660000' "$TMP/persist/soak-summary"
grep -qx 'SOAK_SCHEMA=v2' "$TMP/persist/soak-summary"

# r11 ring schema has 17 columns including TCP/UDP/BPS.
[ "$(tail -n 1 "$TMP/run/ring.csv" | awk -F, '{print NF}')" -eq 17 ]

# Ring remains bounded; shrink limits only in the test copy.
sed -i 's/MAX_LINES=2160/MAX_LINES=5/; s/TRIM_AT=2200/TRIM_AT=7/' "$DST"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1100+i*10))" parent active 100 none 0 170 20 140 80000 160 230 300 500 4 0 playing >/dev/null
done
[ "$(wc -l < "$TMP/run/ring.csv")" -le 7 ]

# Persistent summary is overwrite-only and tiny.
[ "$(wc -c < "$TMP/persist/soak-summary")" -lt 4096 ]

echo 'PASS: Shadow Soak v2 keeps bounded RAM telemetry and compact protocol-aware summary'
