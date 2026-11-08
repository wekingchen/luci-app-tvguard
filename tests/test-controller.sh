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
        tvguard.main.enforce) echo 0 ;;
        tvguard.main.allow_enforcement) echo "${TVGUARD_TEST_ARMED:-0}" ;;
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
sync-reply) echo called >> "$TVGUARD_TEST_REPLY_REPAIR_LOG" ;;
gate) printf '%s\n' "$2" > "$TVGUARD_TEST_GATE" ;;
inspect) case "$(cat "$TVGUARD_TEST_GATE")" in 1) echo blocked;; 0) echo allowed;; *) echo unknown;; esac ;;
sample) cat "$TVGUARD_TEST_SAMPLE" ;;
inspect-reply) echo "${TVGUARD_TEST_OBSERVER:-disabled}" ;;
sample-reply) cat "$TVGUARD_TEST_REPLY" ;;
*) exit 2 ;;
esac
EOFW
cat > "$TMP/audit" <<'EOAUDIT'
#!/bin/sh
printf '%s\n' "${TVGUARD_TEST_AUDIT:-ok}"
case "${TVGUARD_TEST_AUDIT:-ok}" in
    ok) exit 0 ;;
    *) exit 1 ;;
esac
EOAUDIT
chmod +x "$TMP/bin/uci" "$TMP/fw" "$TMP/audit"
echo '0 0 0 0 0 0' > "$TMP/sample"
echo '0 0 0 0' > "$TMP/reply"
: > "$TMP/repair.log"
echo 9 > "$TMP/gate"
export TVGUARD_TEST_SAMPLE="$TMP/sample"
export TVGUARD_TEST_REPLY="$TMP/reply"
export TVGUARD_TEST_REPLY_REPAIR_LOG="$TMP/repair.log"
export TVGUARD_TEST_OBSERVER=disabled
export TVGUARD_TEST_ARMED=0
export TVGUARD_TEST_AUDIT=ok
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
    'AUDIT=/usr/libexec/tvguard-isolation-audit': 'AUDIT='+root+'/audit',
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
check 'assert s["reply_observer"] == "disabled" and s["reply_coverage"] == "unverified"'
check 'assert s["reply_prerouting_pps"] == 0 and s["reply_local_pps"] == 0'

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
sh "$CTL" calibrate playing tencent
echo '1500 240000 170 27000 1280 193000' > "$TMP/sample"
sh "$CTL" tick
status
check 'assert s["used_seconds"] >= 9 and s["used_seconds"] <= 11, s'
check 'assert s["pps"] > 0 and s["tcp_pps"] > 0 and s["udp_pps"] > 0, s'
check 'assert s["traffic_class"] in ("high_traffic","medium_traffic","low_traffic")'
check 'assert s["calibration_label"] == "playing" and s["calibration_app"] == "tencent" and s["calibration_session"] != "none"'
check 'assert s["calibration_phase"] == "running" and s["calibration_active"] == 1'
check 'assert s["calibration_samples"] == 1 and 0 <= s["calibration_elapsed_seconds"] <= 120'
check 'assert s["calibration_remaining_seconds"] > 0 and 0 <= s["calibration_percent"] < 100'
check 'assert s["server_epoch"] > 0'
if sh "$CTL" calibrate paused tencent > "$TMP/out" 2>&1; then
    echo "FAIL: a new session replaced an active calibration" >&2
    exit 1
fi
test -s "$TMP/state/calibration-v3.csv"
grep -q ',playing,tencent,' "$TMP/state/calibration-v3.csv"
# Reply observer is disabled here: never manufacture directional zeros.
[ ! -e "$TMP/state/calibration-v4.csv" ]
# Simulate a completed 120-second calibration without sleeping.
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
p.write_text('\n'.join('CAL_UNTIL=1' if line.startswith('CAL_UNTIL=') else line for line in lines)+'\n')
PY
sh "$CTL" tick
status
check 'assert s["calibration_label"] == "none" and s["calibration_app"] == "none" and s["calibration_session"] == "none"'
check 'assert s["calibration_phase"] == "completed" and s["calibration_active"] == 0'
check 'assert s["calibration_last_label"] == "playing" and s["calibration_last_app"] == "tencent"'
check 'assert s["calibration_last_samples"] == 1 and s["calibration_last_result"] == "completed"'
grep -q 'calibration_end' "$TMP/state/events.log"
# Manual stop must also persist a reason without overwriting the completed CSV.
sh "$CTL" calibrate paused iqiyi
sh "$CTL" calibrate stop
status
check 'assert s["calibration_phase"] == "stopped" and s["calibration_last_app"] == "iqiyi"'
check 'assert s["calibration_last_samples"] == 0 and s["calibration_session"] == "none"'
if sh "$CTL" calibrate stop > "$TMP/out" 2>&1; then exit 1; fi

# Optional passive reply observation is independent from outgoing billing.
# The first snapshot only primes baselines; it must not fabricate a burst.
export TVGUARD_TEST_OBSERVER=ready
echo '100 10000 200 20000' > "$TMP/reply"
sh "$CTL" tick
status
check 'assert s["reply_observer"] == "ready" and s["reply_sample_status"] == "warming_up"'
check 'assert s["reply_prerouting_pps"] == 0 and s["reply_local_pps"] == 0'

python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
lines=['RX_LAST_EPOCH='+str(int(time.time())-10) if line.startswith('RX_LAST_EPOCH=') else line for line in lines]
p.write_text('\n'.join(lines)+'\n')
PY
echo '170 17000 260 29000' > "$TMP/reply"
sh "$CTL" tick
status
check 'assert s["reply_observer"] == "ready" and s["reply_sample_status"] == "observed"'
check 'assert s["reply_prerouting_pps"] == 7 and s["reply_prerouting_bps"] == 700, s'
check 'assert s["reply_local_pps"] == 6 and s["reply_local_bps"] == 900, s'
check 'assert s["reply_coverage"] == "unverified" and s["enforce"] == 0 and s["armed"] == 0'

# A labelled window with a valid reply delta writes the new 12-column
# directional v4 evidence, while v3 remains the canonical legacy dataset.
sh "$CTL" calibrate app_home general
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
lines=[
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else
    'RX_LAST_EPOCH='+str(now-10) if line.startswith('RX_LAST_EPOCH=') else line
    for line in lines
]
p.write_text('\n'.join(lines)+'\n')
PY
echo '1650 270000 200 33000 1400 220000' > "$TMP/sample"
echo '240 31000 330 42000' > "$TMP/reply"
sh "$CTL" tick
test -s "$TMP/state/calibration-v4.csv"
awk -F, 'NF!=12 {exit 1} $3=="app_home" && $4=="general" {found=1} END {exit !found}'     "$TMP/state/calibration-v4.csv"
sh "$CTL" calibration-v4 | grep -q ',app_home,general,'
sh "$CTL" calibrate stop

# FW3 counter reset: never display a huge bogus negative or positive rate.
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
lines=['RX_LAST_EPOCH='+str(int(time.time())-10) if line.startswith('RX_LAST_EPOCH=') else line for line in lines]
p.write_text('\n'.join(lines)+'\n')
PY
echo '2 50 3 60' > "$TMP/reply"
sh "$CTL" tick
status
check 'assert s["reply_sample_status"] == "warming_up" and s["reply_prerouting_pps"] == 0'
check 'assert s["reply_local_pps"] == 0'

export TVGUARD_TEST_OBSERVER=disabled
sh "$CTL" tick
status
check 'assert s["reply_observer"] == "disabled" and s["reply_prerouting_bps"] == 0'
check 'assert s["reply_local_bps"] == 0 and s["reply_coverage"] == "unverified"'

# High reply-only traffic must never create billable activity. Force the
# outgoing counter to stay flat and clear the outgoing activity history.
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
values={}
for line in lines:
    if '=' in line:
        k,v=line.split('=',1)
        values[k]=v
values['LAST_EPOCH']=str(int(time.time())-10)
values['LAST_PACKET_EPOCH']='0'
# Re-arm reply observer baselines ten seconds in the past.
values['RX_LAST_EPOCH']=str(int(time.time())-10)
values['RX_LAST_LAN_COUNT']='2'
values['RX_LAST_LAN_BYTES']='50'
values['RX_LAST_LOCAL_COUNT']='3'
values['RX_LAST_LOCAL_BYTES']='60'
order=[line.split('=',1)[0] for line in lines if '=' in line]
p.write_text('\n'.join(k+'='+values[k] for k in order)+'\n')
PY
export TVGUARD_TEST_OBSERVER=ready
echo '2 50 3 60' > "$TMP/reply"
# Keep outgoing counters unchanged from the previous tick.
before_used="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
# Increase reply counters only.
echo '1002 500050 2003 900060' > "$TMP/reply"
sh "$CTL" tick
status
after_used="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_used" = "$before_used" ]
check 'assert s["activity"] == "silent", s'
check 'assert s["reply_sample_status"] == "observed", s'
check 'assert s["reply_prerouting_pps"] > 0 and s["reply_local_pps"] > 0, s'
check 'assert s["enforce"] == 0 and s["blocked"] == 0, s'

# Missing reply counters after FW3 reload must request an OBSERVER-ONLY repair
# at most once per minute. No call to the gate is made by sync-reply.
export TVGUARD_TEST_OBSERVER=unavailable
sh "$CTL" tick
status
check 'assert s["reply_observer"] == "unavailable" and s["reply_coverage"] == "unverified"'
test "$(wc -l < "$TMP/repair.log")" -eq 1
sh "$CTL" tick
test "$(wc -l < "$TMP/repair.log")" -eq 1

# No invalid labels or hidden enforcement bypass.
if sh "$CTL" calibrate unknown > "$TMP/out" 2>&1; then exit 1; fi
if sh "$CTL" calibrate playing 'bad-app;rm' > "$TMP/out" 2>&1; then exit 1; fi

# First safety key still blocks formal enforcement.
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then exit 1; fi
grep -q 'allow_enforcement=1' "$TMP/out"

# Even with the explicit admin key armed, a non-ok live isolation audit blocks
# enforcement before UCI/gate mutation.
export TVGUARD_TEST_ARMED=1
export TVGUARD_TEST_AUDIT='unsafe:test_violation'
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then
    echo "FAIL: unsafe isolation audit allowed enforcement" >&2
    exit 1
fi
grep -q 'proxy isolation audit is not ok' "$TMP/out"
test "$(cat "$TMP/gate")" = 0

echo "PASS: modes, billing, telemetry, calibration and two-key + live-audit enforcement safety"
