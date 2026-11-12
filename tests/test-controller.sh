#!/bin/sh
# Host-only functional test, never invokes actual router iptables.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/volatile" "$TMP/run"
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
cat > "$TMP/shadow" <<'EOSHADOW'
#!/bin/sh
case "${TVGUARD_TEST_SHADOW:-unknown}" in
    system_home) echo 'system_home system 100' ;;
    app_home) echo 'app_home general 90' ;;
    paused) echo 'paused general 90' ;;
    idle) echo 'idle general 100' ;;
    playing) echo 'playing general 100' ;;
    *) echo 'unknown none 0' ;;
esac
EOSHADOW
chmod +x "$TMP/shadow"
cat > "$TMP/adaptive" <<'EOADAPT'
#!/bin/sh
case "${TVGUARD_TEST_ADAPTIVE:-unready}" in
    idle) echo 'idle 95 6 stable_low 70 138 14 34 idle_overlap 60 180 260 0 0' ;;
    active) echo 'active 100 6 clear_current 70 138 160 233 none 0 220 340 4 0' ;;
    pause_high) echo 'active 95 6 active_votes 70 138 115 184 high_ratio_pause 95 1450 2400 3 24' ;;
    ambiguous) echo 'ambiguous 50 6 overlap 70 138 18 101 bursty_pause 75 260 410 0 0' ;;
    warming) echo 'warming 0 3 need_window 70 138 16 20 none 0 220 300 0 0' ;;
    *) echo 'unready 0 0 no_model 0 0 0 0 none 0 0 0 0 0' ;;
esac
EOADAPT
chmod +x "$TMP/adaptive"
export TVGUARD_TEST_ADAPTIVE=unready

cat > "$TMP/soak" <<'EOSOAK'
#!/bin/sh
case "${TVGUARD_TEST_SOAK:-none}" in
    enter) echo 'enter 0 1 0 0 0 1 1' ;;
    exit) echo 'exit 30 1 1 30 30 2 1' ;;
    *) echo 'none 0 0 0 0 0 0 0' ;;
esac
EOSOAK
chmod +x "$TMP/soak"
export TVGUARD_TEST_SOAK=none

cat > "$TMP/agent-billing" <<'EOAGENTBILL'
#!/bin/sh
case "${TVGUARD_TEST_AGENT_BILLING:-charge}" in
    system_home) echo 'free system_home' ;;
    app_home) echo 'free app_home' ;;
    paused) echo 'free paused' ;;
    playing) echo 'charge playing' ;;
    *) echo 'charge unknown' ;;
esac
EOAGENTBILL
chmod +x "$TMP/agent-billing"
export TVGUARD_TEST_AGENT_BILLING=charge

cat > "$TMP/bark-report" <<'EOBARK'
#!/bin/sh
[ "$1" = test ] || exit 2
awk -F= '$1=="USED_S" {print $2}' "$TVGUARD_TEST_STATE/state" >> "$TVGUARD_TEST_BARK_LOG"
echo '测试推送已发送'
EOBARK
chmod +x "$TMP/bark-report"

cat > "$TMP/data" <<'EODATA'
#!/bin/sh
mode="${TVGUARD_TEST_DATA_MODE:-persistent}"
case "$mode" in persistent|volatile) :;; *) exit 2;; esac
case "${1:-root}" in
    root)
        if [ "$mode" = persistent ]; then
            printf '%s\n' "$TVGUARD_TEST_STATE"
        else
            printf '%s\n' "$TVGUARD_TEST_VOLATILE"
        fi
        ;;
    persistent-root) printf '%s\n' "$TVGUARD_TEST_STATE" ;;
    status)
        if [ "$mode" = persistent ]; then
            printf 'persistent|%s|mounted\n' "$TVGUARD_TEST_STATE"
        else
            printf 'volatile|%s|persistent_mount_unavailable\n' "$TVGUARD_TEST_VOLATILE"
        fi
        ;;
    prepare) : ;;
    *) exit 2 ;;
esac
EODATA
chmod +x "$TMP/data"

cat > "$TMP/learn" <<'EOLEARN'
#!/bin/sh
printf '%s\n' "$*" >> "$TVGUARD_TEST_LEARN_LOG"
cat > "$TVGUARD_TEST_STATE/learning-last.txt" <<EOF
学习分析
状态: 自动测试
会话: $1
计划时长: $3秒
EOF
exit 0
EOLEARN
chmod +x "$TMP/learn"
: > "$TMP/learn.log"
: > "$TMP/bark.log"
export TVGUARD_TEST_BARK_LOG="$TMP/bark.log"
export TVGUARD_TEST_LEARN_LOG="$TMP/learn.log"
export TVGUARD_TEST_STATE="$TMP/state"
export TVGUARD_TEST_VOLATILE="$TMP/volatile"
export TVGUARD_TEST_DATA_MODE=persistent
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
export TVGUARD_TEST_SHADOW=unknown
export TVGUARD_TEST_TX_IDLE_AUTHORITY=0
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
    'SHADOW=/usr/libexec/tvguard-shadow': 'SHADOW='+root+'/shadow',
    'ADAPTIVE=/usr/libexec/tvguard-adaptive': 'ADAPTIVE='+root+'/adaptive',
    'LEARN=/usr/libexec/tvguard-learn': 'LEARN='+root+'/learn',
    'SOAK=/usr/libexec/tvguard-soak': 'SOAK='+root+'/soak',
    'AGENT_BILLING=/usr/libexec/tvguard-agent-billing-hint': 'AGENT_BILLING='+root+'/agent-billing',
    'AGENT_LATEST=/var/run/tvguard-agent-bridge/latest': 'AGENT_LATEST='+root+'/agent-latest',
    'BARK_REPORT=/usr/libexec/tvguard-daily-report': 'BARK_REPORT='+root+'/bark-report',
    'TX_IDLE_BILLING_AUTHORITY=0': 'TX_IDLE_BILLING_AUTHORITY="${TVGUARD_TEST_TX_IDLE_AUTHORITY:-0}"',
    'DATA=/usr/libexec/tvguard-data': 'DATA='+root+'/data',
    'RUN=/var/run/tvguard.state': 'RUN='+root+'/run/runtime',
    'LOCK=/var/run/tvguard.lock': 'LOCK='+root+'/run/lock',
}
for before,after in mapping.items():
    if before not in s:
        raise SystemExit('missing production path anchor: '+before)
    s=s.replace(before,after,1)
Path(dest).write_text(s)
PY
chmod 700 "$CTL"

# N1/BusyBox portability regression: some builds reject fractional sleep.
# Force one stale-lock retry through a mock sleep that accepts integers only.
cat > "$TMP/bin/sleep" <<'EOSLEEP'
#!/bin/sh
case "${1:-}" in
    ''|*[!0-9]*) echo "sleep: invalid number '${1:-}'" >&2; exit 2 ;;
    *) exit 0 ;;
esac
EOSLEEP
chmod +x "$TMP/bin/sleep"
mkdir -p "$TMP/run/lock"
echo 999999 > "$TMP/run/lock/pid"
sh "$CTL" sync
[ ! -d "$TMP/run/lock" ] || { echo "FAIL: stale lock was not recovered" >&2; exit 1; }

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
check 'assert s["bonus_undo_available"] == 0 and s["bonus_limit_seconds"] == 7200'
check 'assert s["policy_reason"] == "none"'
check 'assert s["agent_state"] == "missing" and s["agent_package"] == "unknown", s'

sh "$CTL" bonus 15
status
check 'assert s["bonus_seconds"] == 900 and s["remaining_seconds"] >= 900'
check 'assert s["bonus_undo_available"] == 1'
sh "$CTL" bonus 30
status
check 'assert s["bonus_seconds"] == 2700 and s["bonus_undo_available"] == 1'
sh "$CTL" bonus undo
status
check 'assert s["bonus_seconds"] == 900 and s["bonus_undo_available"] == 0'
grep -q 'reward_revoke|-30 分钟' "$TMP/state/events.log"
if sh "$CTL" bonus undo > "$TMP/out" 2>&1; then exit 1; fi
if sh "$CTL" bonus 999 > "$TMP/out" 2>&1; then exit 1; fi

# Parent mode is a persistent usage identity, not temporary child allowance.
sh "$CTL" mode parent
status
check 'assert s["mode"] == "parent" and s["parent_until"] == 0 and s["policy_reason"] == "none"'
sh "$CTL" brief > "$TMP/brief"
grep -q '计时: 已暂停（家长模式不计儿童额度）' "$TMP/brief"
# A stale cached UI must not turn an old timed-parent request into indefinite access.
if sh "$CTL" mode parent 30 > "$TMP/out" 2>&1; then
    echo "FAIL: legacy timed parent command was accepted" >&2
    exit 1
fi
grep -q 'no longer accepts a duration' "$TMP/out"
status
check 'assert s["mode"] == "parent" and s["parent_until"] == 0'
sh "$CTL" mode locked
status
check 'assert s["mode"] == "locked" and s["would_block"] == 1 and s["blocked"] == 0'
sh "$CTL" brief > "$TMP/brief"
grep -q '计时: 已暂停（锁定模式）' "$TMP/brief"
check 'assert s["policy_reason"] == "locked"'
sh "$CTL" mode child

# Migration only: a pre-v0.1.7 timed parent state is allowed to expire once,
# preventing an old temporary authorization from silently becoming permanent.
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
out=[]
for line in lines:
    if line.startswith('MODE='):
        out.append('MODE=parent')
    elif line.startswith('PARENT_UNTIL='):
        out.append('PARENT_UNTIL='+str(int(time.time())-1))
    else:
        out.append(line)
p.write_text('\n'.join(out)+'\n')
PY
sh "$CTL" sync
status
check 'assert s["mode"] == "child" and s["parent_until"] == 0'

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
agent_now="$(date +%s)"
printf '%s|com.example.video|com.example.video.PlayerActivity|1|1|%s|41\n'     "$agent_now" "$((agent_now * 1000))" > "$TMP/agent-latest"
echo '1500 240000 170 27000 1280 193000' > "$TMP/sample"
sh "$CTL" tick
status
check 'assert s["used_seconds"] >= 9 and s["used_seconds"] <= 11, s'
check 'assert s["watch_seconds"] == s["used_seconds"] and s["previous_day_date"] == "none", s'
check 'assert s["pps"] > 0 and s["tcp_pps"] > 0 and s["udp_pps"] > 0, s'
check 'assert s["traffic_class"] in ("high_traffic","medium_traffic","low_traffic")'
check 'assert s["calibration_label"] == "playing" and s["calibration_app"] == "tencent" and s["calibration_session"] != "none"'
check 'assert s["calibration_phase"] == "running" and s["calibration_active"] == 1'
check 'assert s["calibration_samples"] == 1 and 0 <= s["calibration_elapsed_seconds"] <= 120'
check 'assert s["calibration_remaining_seconds"] > 0 and 0 <= s["calibration_percent"] < 100'
check 'assert s["server_epoch"] > 0'
check 'assert s["agent_state"] == "fresh" and s["agent_package"] == "com.example.video", s'
check 'assert s["agent_activity"] == "com.example.video.PlayerActivity" and s["agent_audio_active"] == 1 and s["agent_screen_on"] == 1, s'
check 'assert s["agent_report_seq"] == 41 and 0 <= s["agent_age_seconds"] <= 20, s'
if sh "$CTL" calibrate paused tencent > "$TMP/out" 2>&1; then
    echo "FAIL: a new session replaced an active calibration" >&2
    exit 1
fi
test -s "$TMP/state/calibration-v3.csv"
grep -q ',playing,tencent,' "$TMP/state/calibration-v3.csv"
test -s "$TMP/state/calibration-v5.csv"
awk -F, 'NF!=14 {exit 1} $3=="playing" && $4=="fresh" && $6=="com.example.video" && $7=="com.example.video.PlayerActivity" && $8==1 && $9==1 && $10==41 {found=1} END {exit !found}' "$TMP/state/calibration-v5.csv"
sh "$CTL" calibration-v5 | grep -q ',playing,fresh,'
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
# New learning UI may choose 60/180/300 seconds and automatic analysis
# receives the exact session duration after completion.
sh "$CTL" calibrate system_home 180
status
check 'assert s["calibration_duration_seconds"] == 180 and s["calibration_remaining_seconds"] > 0, s'
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
p.write_text('\n'.join('CAL_UNTIL=1' if line.startswith('CAL_UNTIL=') else line for line in lines)+'\n')
PY
sh "$CTL" tick
status
check 'assert s["calibration_last_duration_seconds"] == 180 and s["calibration_last_label"] == "system_home", s'
grep -q 'system_home 180 system completed' "$TMP/learn.log"
test -s "$TMP/state/learning-last.txt"
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
check 'assert 5 <= s["reply_prerouting_pps"] <= 7 and 580 <= s["reply_prerouting_bps"] <= 780, s'
check 'assert 5 <= s["reply_local_pps"] <= 6 and 750 <= s["reply_local_bps"] <= 1000, s'
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
check 'assert s["activity"] == "silent" and s["billing_state"] == "idle_silent", s'
check 'assert s["reply_sample_status"] == "observed", s'
check 'assert s["reply_prerouting_pps"] > 0 and s["reply_local_pps"] > 0, s'
check 'assert s["enforce"] == 0 and s["blocked"] == 0, s'


# P0 low-bitrate safety: TX-only idle labels are diagnostic-only by default.
# Reproduce the dangerous shape directly: Adaptive says stable_low/idle while
# packets are still flowing. Child time MUST continue to increase.
export TVGUARD_TEST_TX_IDLE_AUTHORITY=0
export TVGUARD_TEST_ADAPTIVE=idle
export TVGUARD_TEST_SHADOW=system_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 220)) $(($2 + 48000)) $(($3 + 140)) $(($4 + 18000)) $(($5 + 80)) $(($6 + 30000))" > "$TMP/sample"
before_p0_adaptive="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
sh "$CTL" tick
status
after_p0_adaptive="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
delta_p0_adaptive=$((after_p0_adaptive-before_p0_adaptive))
[ "$delta_p0_adaptive" -ge 9 ] && [ "$delta_p0_adaptive" -le 11 ]
check 'assert s["adaptive_state"]=="idle" and s["adaptive_reason"]=="stable_low", s'
check 'assert s["billing_state"]=="charge" and s["idle_reason"]=="none" and s["activity"]=="active", s'

# The legacy Shadow fallback must not regain free-time authority when Adaptive
# is unready. A low-traffic/system-home hint remains visible but still charges.
export TVGUARD_TEST_ADAPTIVE=unready
export TVGUARD_TEST_SHADOW=system_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 60)) $(($2 + 12000)) $(($3 + 10)) $(($4 + 2000)) $(($5 + 50)) $(($6 + 10000))" > "$TMP/sample"
before_p0_shadow="$after_p0_adaptive"
sh "$CTL" tick
status
after_p0_shadow="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
delta_p0_shadow=$((after_p0_shadow-before_p0_shadow))
[ "$delta_p0_shadow" -ge 9 ] && [ "$delta_p0_shadow" -le 11 ]
check 'assert s["shadow_label"]=="system_home" and s["adaptive_state"]=="unready", s'
check 'assert s["billing_state"]=="charge" and s["idle_reason"]=="none", s'

# Conservative Agent-assisted formal billing: explicit homes and only a
# bridge-confirmed paused state are free. Generic TX idle remains chargeable.
export TVGUARD_TEST_TX_IDLE_AUTHORITY=0
export TVGUARD_TEST_ADAPTIVE=ambiguous
export TVGUARD_TEST_SHADOW=unknown

# Explicit system_home: active network traffic is present, but child time does not increase.
export TVGUARD_TEST_AGENT_BILLING=system_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 400)) $(($2 + 80000)) $(($3 + 40)) $(($4 + 8000)) $(($5 + 360)) $(($6 + 72000))" > "$TMP/sample"
before_home="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
sh "$CTL" tick
status
after_home="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_home" = "$before_home" ]
check 'assert s["activity"]=="active" and s["billing_state"]=="idle_verified" and s["idle_reason"]=="system_home", s'

# Explicit app_home: same narrow exemption.
export TVGUARD_TEST_AGENT_BILLING=app_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 300)) $(($2 + 60000)) $(($3 + 30)) $(($4 + 6000)) $(($5 + 270)) $(($6 + 54000))" > "$TMP/sample"
sh "$CTL" tick
status
after_app_home="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_app_home" = "$after_home" ]
check 'assert s["billing_state"]=="idle_verified" and s["idle_reason"]=="app_home", s'

# Explicit confirmed pause is now a narrow exemption.
export TVGUARD_TEST_AGENT_BILLING=paused
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 200)) $(($2 + 40000)) $(($3 + 20)) $(($4 + 4000)) $(($5 + 180)) $(($6 + 36000))" > "$TMP/sample"
sh "$CTL" tick
status
after_paused="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_paused" = "$after_app_home" ]
check 'assert s["billing_state"]=="idle_verified" and s["idle_reason"]=="paused", s'
export TVGUARD_TEST_AGENT_BILLING=charge

# Keep the previous smart-idle state machine covered as dormant code. Tests may
# opt it back in, but production r12 has the gate hardcoded off.
export TVGUARD_TEST_TX_IDLE_AUTHORITY=1
export TVGUARD_TEST_ADAPTIVE=unready

# Smart billing: a verified idle hint must persist for 30 seconds before
# pausing child time. The first two 10s windows still charge conservatively.
export TVGUARD_TEST_OBSERVER=disabled
export TVGUARD_TEST_SHADOW=system_home
before_smart="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
for step in 1 2 3; do
    python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
    set -- $(cat "$TMP/sample")
    echo "$(($1 + 100)) $(($2 + 10000)) $(($3 + 20)) $(($4 + 2000)) $(($5 + 70)) $(($6 + 7000))" > "$TMP/sample"
    sh "$CTL" tick
done
status
after_idle="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
delta_idle=$((after_idle - before_smart))
[ "$delta_idle" -ge 18 ] && [ "$delta_idle" -le 22 ]
check 'assert s["billing_state"] == "idle_verified" and s["idle_reason"] == "idle", s'
check 'assert s["idle_streak_seconds"] >= 30, s'

# Once idle is verified, switching between trusted idle labels must not
# restart confirmation or bill another 10-second window. This reproduces the
# N1 App-home -> system-home boundary transition seen in real traffic.
export TVGUARD_TEST_SHADOW=app_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 100)) $(($2 + 10000)) $(($3 + 20)) $(($4 + 2000)) $(($5 + 70)) $(($6 + 7000))" > "$TMP/sample"
before_transition="$after_idle"
sh "$CTL" tick
status
after_transition="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_transition" = "$before_transition" ]
check 'assert s["billing_state"] == "idle_verified" and s["idle_reason"] == "idle", s'
check 'assert s["idle_streak_seconds"] >= 40, s'

export TVGUARD_TEST_SHADOW=system_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 100)) $(($2 + 10000)) $(($3 + 20)) $(($4 + 2000)) $(($5 + 70)) $(($6 + 7000))" > "$TMP/sample"
sh "$CTL" tick
status
after_transition2="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_transition2" = "$before_transition" ]
check 'assert s["billing_state"] == "idle_verified" and s["idle_reason"] == "idle", s'
check 'assert s["idle_streak_seconds"] >= 50, s'

# After verified idle, one or two low-traffic unknown windows are held for
# at most 20 seconds and must not consume child time. Keep each synthetic
# window at 9 seconds so CI wall-clock rollover cannot turn the second step
# into 21 seconds and exercise the intentionally-expired branch instead.
export TVGUARD_TEST_SHADOW=unknown
for grace_step in 1 2; do
    python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-9) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
    set -- $(cat "$TMP/sample")
    echo "$(($1 + 160)) $(($2 + 30000)) $(($3 + 20)) $(($4 + 2000)) $(($5 + 140)) $(($6 + 28000))" > "$TMP/sample"
    before_grace="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
    sh "$CTL" tick
    status
    after_grace="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
    [ "$after_grace" = "$before_grace" ]
    check 'assert s["billing_state"] == "idle_grace" and 1 <= s["idle_grace_seconds"] <= 20, s'
done

# Unknown evidence must resume charging immediately and clear the idle streak.
export TVGUARD_TEST_SHADOW=unknown
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join(
    'LAST_EPOCH='+str(now-10) if line.startswith('LAST_EPOCH=') else line
    for line in lines
)+'\n')
PY
set -- $(cat "$TMP/sample")
# High-activity unknown must resume billing immediately.
echo "$(($1 + 1500)) $(($2 + 120000)) $(($3 + 300)) $(($4 + 30000)) $(($5 + 1100)) $(($6 + 90000))" > "$TMP/sample"
before_unknown="$after_idle"
sh "$CTL" tick
status
after_unknown="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
delta_unknown=$((after_unknown - before_unknown))
[ "$delta_unknown" -ge 9 ] && [ "$delta_unknown" -le 11 ]
check 'assert s["billing_state"] == "charge" and s["idle_reason"] == "none" and s["idle_streak_seconds"] == 0, s'

# Adaptive Phase 1: learned idle bypasses single-frame shadow instability
# only after the rolling model itself says idle.
export TVGUARD_TEST_ADAPTIVE=idle
export TVGUARD_TEST_SHADOW=unknown
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join('LAST_EPOCH='+str(now-10) if x.startswith('LAST_EPOCH=') else x for x in lines)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 120)) $(($2 + 12000)) $(($3 + 10)) $(($4 + 1000)) $(($5 + 100)) $(($6 + 11000))" > "$TMP/sample"
before_adaptive="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
sh "$CTL" tick
status
after_adaptive="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ "$after_adaptive" = "$before_adaptive" ]
check 'assert s["adaptive_state"]=="idle" and s["billing_state"]=="idle_verified" and s["idle_reason"]=="adaptive", s'

# Clear learned playback must resume charging immediately even if shadow is unknown.
export TVGUARD_TEST_ADAPTIVE=active
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join('LAST_EPOCH='+str(now-10) if x.startswith('LAST_EPOCH=') else x for x in lines)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 1600)) $(($2 + 180000)) $(($3 + 700)) $(($4 + 70000)) $(($5 + 900)) $(($6 + 110000))" > "$TMP/sample"
before_active="$after_adaptive"
sh "$CTL" tick
status
after_active="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ $((after_active-before_active)) -ge 9 ] && [ $((after_active-before_active)) -le 11 ]
check 'assert s["adaptive_state"]=="active" and s["billing_state"]=="charge", s'
# Phase 2A pause hints are diagnostic only. A high-ratio pause candidate
# must remain billable because its Phase 1 state is still active.
export TVGUARD_TEST_ADAPTIVE=pause_high
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join('LAST_EPOCH='+str(now-10) if x.startswith('LAST_EPOCH=') else x for x in lines)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 1200)) $(($2 + 1600000)) $(($3 + 20)) $(($4 + 20000)) $(($5 + 1180)) $(($6 + 1580000))" > "$TMP/sample"
before_pause_hint="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
export TVGUARD_TEST_SOAK=enter
sh "$CTL" tick
status
after_pause_hint="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ $((after_pause_hint-before_pause_hint)) -ge 9 ] && [ $((after_pause_hint-before_pause_hint)) -le 11 ]
check 'assert s["adaptive_state"]=="active" and s["adaptive_pause_hint"]=="high_ratio_pause" and s["adaptive_pause_score"]==95 and s["billing_state"]=="charge", s'
check 'assert s["adaptive_bp_p50"]==1450 and s["adaptive_bp_p90"]==2400 and s["adaptive_trend_percent"]==24, s'
grep -q '|soak_pause_enter|' "$TMP/state/events.log"

# Soak exit is also observation-only: playback remains charge and no gate
# mutation can be requested by the helper output.
export TVGUARD_TEST_ADAPTIVE=active
export TVGUARD_TEST_SOAK=exit
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
now=int(time.time())
p.write_text('\n'.join('LAST_EPOCH='+str(now-10) if x.startswith('LAST_EPOCH=') else x for x in lines)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1 + 1600)) $(($2 + 180000)) $(($3 + 700)) $(($4 + 70000)) $(($5 + 900)) $(($6 + 110000))" > "$TMP/sample"
before_soak_exit="$(sh "$CTL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["used_seconds"])')"
sh "$CTL" tick
status
after_soak_exit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["used_seconds"])' "$TMP/status.json")"
[ $((after_soak_exit-before_soak_exit)) -ge 9 ] && [ $((after_soak_exit-before_soak_exit)) -le 11 ]
check 'assert s["adaptive_state"]=="active" and s["billing_state"]=="charge" and s["blocked"]==0, s'
grep -q '|soak_pause_exit|' "$TMP/state/events.log"
test "$(cat "$TMP/gate")" = 0

export TVGUARD_TEST_SOAK=none
export TVGUARD_TEST_ADAPTIVE=unready

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
export TVGUARD_TEST_ARMED=0
export TVGUARD_TEST_AUDIT=ok

# Delayed-mount regression: a /var/run snapshot created while the durable
# mount is unavailable must not shadow the real mmc state after the mount
# returns. Persist parent mode in the durable store first.
export TVGUARD_TEST_DATA_MODE=persistent
sh "$CTL" mode parent
grep -qx 'DATA_ROOT_MODE=persistent' "$TMP/run/runtime"
grep -qx 'MODE=parent' "$TMP/state/state"

# Lose the mount. The persistent-mode runtime must be discarded; a volatile
# sync creates a RAM-only child snapshot marked volatile.
export TVGUARD_TEST_DATA_MODE=volatile
sh "$CTL" sync
grep -qx 'DATA_ROOT_MODE=volatile' "$TMP/run/runtime"
grep -qx 'MODE=child' "$TMP/volatile/state"

# Mount returns. The volatile runtime must be discarded and the durable
# parent snapshot must become authoritative immediately.
export TVGUARD_TEST_DATA_MODE=persistent
status
check 'assert s["mode"]=="parent" and s["parent_until"]==0, s'
grep -qx 'MODE=parent' "$TMP/state/state"
# status only reads durable state; recreate the active runtime before editing.
sh "$CTL" sync

# Parent mode must leave child viewing and child quota unchanged.
export TVGUARD_TEST_AGENT_BILLING=charge
set -- $(sh "$CTL" status | python3 -c 'import json,sys; s=json.load(sys.stdin);print(s["used_seconds"],s["watch_seconds"])')
old_child="$1"; old_watch="$2"
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
p.write_text('\n'.join('LAST_EPOCH='+str(int(time.time())-10) if x.startswith('LAST_EPOCH=') else x for x in lines)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1+500)) $(($2+100000)) $(($3+250)) $(($4+50000)) $(($5+250)) $(($6+50000))" > "$TMP/sample"
sh "$CTL" tick
set -- $(sh "$CTL" status | python3 -c 'import json,sys; s=json.load(sys.stdin);print(s["used_seconds"],s["watch_seconds"])')
[ "$1" -eq "$old_child" ]
[ "$2" -eq "$old_watch" ]

# The current Agent home exemption applies to the child-mode counter too.
old_watch="$2"
export TVGUARD_TEST_AGENT_BILLING=app_home
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
p.write_text('\n'.join('LAST_EPOCH='+str(int(time.time())-10) if x.startswith('LAST_EPOCH=') else x for x in lines)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1+500)) $(($2+100000)) $(($3+250)) $(($4+50000)) $(($5+250)) $(($6+50000))" > "$TMP/sample"
sh "$CTL" tick
status
check 'assert s["billing_state"]=="idle_verified" and s["idle_reason"]=="app_home",s'
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["watch_seconds"])' "$TMP/status.json")" -eq "$old_watch" ]

# Observation mode: keep counting when child usage already exceeds quota.
sh "$CTL" mode child
export TVGUARD_TEST_AGENT_BILLING=charge
quota="$(sh "$CTL" status | python3 -c 'import json,sys;print(json.load(sys.stdin)["quota_seconds"])')"
python3 - "$TMP/run/runtime" "$quota" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
quota=int(sys.argv[2])
lines=p.read_text().splitlines()
out=[]
for x in lines:
    if x.startswith('LAST_EPOCH='): x='LAST_EPOCH='+str(int(time.time())-10)
    if x.startswith('USED_S='): x='USED_S='+str(quota+120)
    if x.startswith('WATCH_S='): x='WATCH_S='+str(quota+120)
    out.append(x)
p.write_text('\n'.join(out)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1+500)) $(($2+100000)) $(($3+250)) $(($4+50000)) $(($5+250)) $(($6+50000))" > "$TMP/sample"
sh "$CTL" tick
status
check 'assert s["enforce"]==0 and s["used_seconds"]>s["quota_seconds"] and s["watch_seconds"]==s["used_seconds"],s'

# Day boundary archives only child-mode viewing and resets today's total.
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
out=[]
for x in lines:
    if x.startswith('TODAY='): x='TODAY=2026-11-10'
    if x.startswith('WATCH_S='): x='WATCH_S=1234'
    if x.startswith('USED_S='): x='USED_S=1234'
    out.append(x)
p.write_text('\n'.join(out)+'\n')
PY
sh "$CTL" sync
status
check 'assert s["watch_seconds"]==0 and s["previous_day_date"]=="2026-11-10" and s["previous_day_seconds"]==1234,s'

# Older r18 all-mode summaries must not be mistaken for child-only viewing.
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
out=[]
for x in lines:
    if x.startswith('WATCH_SCOPE='): x='WATCH_SCOPE=legacy'
    if x.startswith('WATCH_S='): x='WATCH_S=9999'
    if x.startswith('USED_S='): x='USED_S=125'
    if x.startswith('PREV_DATE='): x='PREV_DATE=2026-11-09'
    if x.startswith('PREV_WATCH_S='): x='PREV_WATCH_S=9999'
    out.append(x)
p.write_text('\n'.join(out)+'\n')
PY
sh "$CTL" sync
status
check 'assert s["watch_seconds"]==125 and s["used_seconds"]==125 and s["previous_day_date"]=="none" and s["previous_day_seconds"]==0,s'

# The admin's live test refreshes counters and saves the exact child-only
# snapshot before it invokes Bark; it cannot enable enforcement.
sh "$CTL" mode child
export TVGUARD_TEST_AGENT_BILLING=charge
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1])
s=p.read_text()
p.write_text('\n'.join(
    'LAST_EPOCH='+str(int(time.time())-10) if x.startswith('LAST_EPOCH=') else x
    for x in s.splitlines()
)+'\n')
PY
set -- $(cat "$TMP/sample")
echo "$(($1+500)) $(($2+100000)) $(($3+250)) $(($4+50000)) $(($5+250)) $(($6+50000))" > "$TMP/sample"
previous="$(sh "$CTL" status | python3 -c 'import json,sys;print(json.load(sys.stdin)["used_seconds"])')"
sh "$CTL" bark-test > "$TMP/bark-response"
grep -q '测试推送已发送' "$TMP/bark-response"
reported="$(tail -n 1 "$TMP/bark.log")"
[ "$reported" -ge "$((previous+9))" ] && [ "$reported" -le "$((previous+11))" ]
status
check 'assert s["used_seconds"]==s["watch_seconds"] and s["enforce"]==0,s'
[ "$(cat "$TMP/gate")" = 0 ]

echo "PASS: child-only watching, uncapped quota, live Bark snapshot and migration safety"
