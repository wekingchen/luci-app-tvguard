#!/bin/sh
# Host-only functional test, never invokes actual router iptables.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/run"
cat > "$TMP/bin/uci" <<'EOUCI'
#!/bin/sh
if [ "${1:-}" = -q ]; then shift; fi
case "${1:-}" in
get)
    case "${2:-}" in
        tvguard.main.enforce|tvguard.main.allow_enforcement) echo 0 ;;
        tvguard.main.weekday_minutes) echo 60 ;;
        tvguard.main.weekend_minutes) echo 120 ;;
        tvguard.main.max_bonus_minutes) echo 120 ;;
        tvguard.main.silence_seconds) echo 60 ;;
        tvguard.main.allow_start|tvguard.main.allow_end) echo 00:00 ;;
        *) exit 1 ;;
    esac ;;
*) echo "unexpected UCI action: $*" >&2; exit 1 ;;
esac
EOUCI
cat > "$TMP/fw" <<'EOFW'
#!/bin/sh
case "$1" in
sync) exit 0 ;;
gate) printf '%s\n' "$2" > "$TVGUARD_TEST_GATE" ;;
inspect) case "$(cat "$TVGUARD_TEST_GATE")" in 1) echo blocked;; 0) echo allowed;; *) echo unknown;; esac ;;
sample) cat "$TVGUARD_TEST_SAMPLE" ;;
*) exit 2 ;;
esac
EOFW
chmod +x "$TMP/bin/uci" "$TMP/fw"
echo '0 0 0 0 0 0' > "$TMP/sample"
echo 9 > "$TMP/gate"
export TVGUARD_TEST_SAMPLE="$TMP/sample"
export TVGUARD_TEST_GATE="$TMP/gate"
# Rewrite a disposable copy only. Production controller has no env path overrides.
CTL="$TMP/controller"
python3 - "$ROOT/root/usr/libexec/tvguardctl" "$CTL" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dest,root=sys.argv[1:]
s=Path(src).read_text()
mapping={
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin': 'PATH='+root+'/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    'FW=/usr/libexec/tvguard-fw': 'FW='+root+'/fw',
    'RUN=/var/run/tvguard.state': 'RUN='+root+'/run/runtime',
    'DIR=/etc/tvguard': 'DIR='+root+'/state',
    'LOCK=/var/run/tvguard.lock': 'LOCK='+root+'/run/lock',
}
for before,after in mapping.items():
    if before not in s:
        raise SystemExit('missing production path anchor: '+before)
    s=s.replace(before,after,1)
Path(dest).write_text(s)
PY
chmod 700 "$CTL"

status() { sh "$CTL" status > "$TMP/status.json"; }
check() { python3 - "$TMP/status.json" "$1" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
exec(sys.argv[2], {"s":s})
PY
}

sh "$CTL" sync
status
check 'assert s["enforce"] == 0 and s["armed"] == 0 and s["mode"] == "child"'
check 'assert s["pps"] == 0 and s["calibration_label"] == "none"'

sh "$CTL" bonus 15
status
check 'assert s["bonus_seconds"] == 900 and s["remaining_seconds"] >= 900'
sh "$CTL" bonus undo
status
check 'assert s["bonus_seconds"] == 0'
if sh "$CTL" bonus undo > "$TMP/out" 2>&1; then exit 1; fi
if sh "$CTL" bonus 999 > "$TMP/out" 2>&1; then exit 1; fi

sh "$CTL" mode parent 30
status
check 'assert s["mode"] == "parent" and s["parent_until"] > 0'
sh "$CTL" mode locked
status
check 'assert s["mode"] == "locked" and s["would_block"] == 1 and s["blocked"] == 0'
sh "$CTL" mode child

# Prime the counter baseline: never bill 20 seconds when daemon starts.
echo '500 100000 100 20000 350 70000' > "$TMP/sample"
sh "$CTL" tick
status
check 'assert s["used_seconds"] == 0, s'
check 'assert s["pps"] == 0, s'

# Artificially simulate 10 elapsed seconds without sleeping.
python3 - "$TMP/run/runtime" <<'PY'
import pathlib,sys,time
p=pathlib.Path(sys.argv[1])
s=p.read_text()
s=s.replace(f'LAST_EPOCH={int(time.time())}', f'LAST_EPOCH={int(time.time())-10}')
if 'LAST_EPOCH=' not in s: raise RuntimeError("no LAST_EPOCH")
# Robustly set last timestamp even across second boundaries
s='\n'.join('LAST_EPOCH='+str(int(time.time())-10) if x.startswith('LAST_EPOCH=') else x for x in s.splitlines())+'\n'
p.write_text(s)
PY
sh "$CTL" calibrate playing
echo '1500 240000 170 27000 1280 193000' > "$TMP/sample"
sh "$CTL" tick
status
check 'assert s["used_seconds"] >= 9 and s["used_seconds"] <= 11, s'
check 'assert s["pps"] > 0 and s["tcp_pps"] > 0 and s["udp_pps"] > 0, s'
check 'assert s["traffic_class"] in ("high_traffic","medium_traffic","low_traffic")'
check 'assert s["calibration_label"] == "playing"'
test -s "$TMP/state/calibration.csv"
grep -q ',playing,' "$TMP/state/calibration.csv"
sh "$CTL" calibrate stop
status
check 'assert s["calibration_label"] == "none"'

# No invalid labels or hidden enforcement bypass.
if sh "$CTL" calibrate unknown > "$TMP/out" 2>&1; then exit 1; fi
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then exit 1; fi
test "$(cat "$TMP/gate")" = 0
echo "PASS: syntax, mode, rewards, startup timebase, telemetry, labels, fail-safe"
