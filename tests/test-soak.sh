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


# Restore production-sized ring limits after the bounded-ring test so the
# temporal observer can inspect its full 12-window history.
sed -i 's/MAX_LINES=5/MAX_LINES=2160/; s/TRIM_AT=7/TRIM_AT=2200/' "$DST"

# r14 -> r15 temporal migration: legacy temporal state may contain an
# impossible epoch-sized duration because r13 left candidate_start=0. Reset
# only temporal aggregates; keep the main Soak evidence epoch intact.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
cat > "$TMP/run/state" <<'EOF'
SOAK_SCHEMA=v2
TOTAL_SAMPLES=77
HIGH_RATIO_ENTERS=3
HIGH_RATIO_EXITS=3
TEMPORAL_LAST_HINT=stable_low_plateau
TEMPORAL_CANDIDATE_START=0
TEMPORAL_CANDIDATE_SAMPLES=99
TEMPORAL_ENTERS=4
TEMPORAL_EXITS=4
TEMPORAL_SECONDS=1794240119
TEMPORAL_MAX_SECONDS=1794240119
TEMPORAL_LAST_DURATION=1794240119
EOF
run 1900 parent active 100 none 0 80 70 10 9000 60 100 100 200 2 0 playing >/dev/null
grep -qx 'TEMPORAL_STATE_SCHEMA=v2' "$TMP/run/state"
grep -qx 'TEMPORAL_LAST_HINT=none' "$TMP/run/state"
grep -qx 'TEMPORAL_CANDIDATE_START=0' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=0' "$TMP/run/state"
grep -qx 'TEMPORAL_EXITS=0' "$TMP/run/state"
grep -qx 'TEMPORAL_SECONDS=0' "$TMP/run/state"
grep -qx 'TEMPORAL_MAX_SECONDS=0' "$TMP/run/state"
grep -qx 'TEMPORAL_LAST_DURATION=0' "$TMP/run/state"
grep -qx 'TOTAL_SAMPLES=78' "$TMP/run/state"
grep -qx 'HIGH_RATIO_ENTERS=3' "$TMP/run/state"

# Pure or mostly silent windows are already handled by idle_silent and must
# not pollute stable_low_plateau statistics.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
i=0
while [ "$i" -lt 12 ]; do
    i=$((i+1))
    run "$((1950+i*10))" parent idle 95 idle_overlap 60 0 0 0 0 0 0 0 0 0 0 unknown >/dev/null
done
grep -qx 'TEMPORAL_HINT=none' "$TMP/run/state"
grep -qx 'TEMPORAL_P50=0' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=0' "$TMP/run/state"

# One stray non-zero window inside an otherwise silent history is still not
# positive idle evidence; the median must be non-zero before a plateau exists.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
i=0
for pps in 0 0 0 0 0 0 0 0 0 0 0 5; do
    i=$((i+1))
    run "$((2100+i*10))" parent idle 95 idle_overlap 60 "$pps" 0 "$pps" "$((pps*300))" 0 5 0 0 0 0 unknown >/dev/null
done
grep -qx 'TEMPORAL_HINT=none' "$TMP/run/state"
grep -qx 'TEMPORAL_P50=0' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=0' "$TMP/run/state"

# P1-C temporal regression: a genuinely stable low plateau may be observed as
# a Shadow-only candidate after ~2 minutes. It still has no billing authority.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
i=0
for pps in 9 11 9 9 10 9 10 9 9 10 9 10; do
    i=$((i+1))
    run "$((2000+i*10))" parent idle 95 idle_overlap 60 "$pps" 1 "$((pps-1))" 3000 10 11 250 350 0 0 idle >/dev/null
done
grep -qx 'TEMPORAL_HINT=stable_low_plateau' "$TMP/run/state"
grep -qx 'TEMPORAL_SCORE=70' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=1' "$TMP/run/state"
grep -qx 'TEMPORAL_P90=10' "$TMP/run/state"
grep -qx 'TEMPORAL_SPREAD=1' "$TMP/run/state"

# Real N1 paused field sample: a slightly wider but still low/stable plateau
# (P10/P50/P90 about 5/5/13, spread 8, max 16) must be observable too.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
i=0
for pps in 5 5 5 6 5 5 6 5 13 16 5 6; do
    i=$((i+1))
    run "$((2500+i*10))" parent idle 95 idle_overlap 60 "$pps" 1 "$((pps>1 ? pps-1 : 0))" 1800 6 13 250 350 0 0 idle >/dev/null
done
grep -qx 'TEMPORAL_HINT=stable_low_plateau' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=1' "$TMP/run/state"
grep -qx 'TEMPORAL_SPREAD=8' "$TMP/run/state"

# State must persist across ticks instead of being reset to zero.
run 2630 parent idle 95 idle_overlap 60 6 1 5 1800 6 13 250 350 0 0 idle >/dev/null
grep -qx 'TEMPORAL_ENTERS=1' "$TMP/run/state"
grep -qx 'TEMPORAL_CANDIDATE_SAMPLES=2' "$TMP/run/state"

# Real N1 regression: confirmed continuous Mango 576p playback entered a
# low-traffic UDP-heavy regime for ~251 seconds. Its burst cadence must NOT
# trigger stable_low_plateau even though many individual windows are <=20 PPS.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
i=0
for pps in 26 3 23 4 24 2 18 10 16 15 11 35 3 25 2 41 2 41 2 39 3 32 22 39 17; do
    i=$((i+1))
    run "$((3000+i*10))" parent idle 95 idle_overlap 60 "$pps" 1 "$((pps>1 ? pps-1 : 0))" 3000 17 39 200 500 0 0 unknown >/dev/null
done
grep -qx 'TEMPORAL_HINT=none' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=0' "$TMP/run/state"

# A TCP-heavy confirmed 576p regime also stays outside the candidate.
rm -f "$TMP/run/state" "$TMP/persist/soak-summary" "$TMP/run/ring.csv" "$TMP/run/schema"
i=0
for pps in 69 163 116 59 76 87 75 84 70 148 48 77 104 167 105 120 114 75 64 67 40 73 46 41 72 52 69 88 134 55; do
    i=$((i+1))
    run "$((4000+i*10))" parent ambiguous 50 none 0 "$pps" "$((pps>8 ? pps-8 : 0))" 8 8000 75 134 100 200 0 0 unknown >/dev/null
done
grep -qx 'TEMPORAL_HINT=none' "$TMP/run/state"
grep -qx 'TEMPORAL_ENTERS=0' "$TMP/run/state"


echo 'PASS: Shadow Soak keeps bounded telemetry and rejects real 576p temporal false positives'
