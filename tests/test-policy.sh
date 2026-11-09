#!/bin/sh
# Deterministic policy/state unit tests. All time, UCI and firewall inputs are mocked.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/run"

cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
[ "${1:-}" = get ] || exit 2
case "${2:-}" in
    tvguard.main.enforce) echo "${TVG_ENFORCE:-0}" ;;
    tvguard.main.allow_enforcement) echo "${TVG_ARMED:-0}" ;;
    tvguard.main.weekday_minutes) echo "${TVG_WEEKDAY_MINUTES:-60}" ;;
    tvguard.main.weekend_minutes) echo "${TVG_WEEKEND_MINUTES:-120}" ;;
    tvguard.main.max_bonus_minutes) echo "${TVG_BONUS_MAX:-120}" ;;
    tvguard.main.silence_seconds) echo "${TVG_SILENCE:-60}" ;;
    tvguard.main.allow_start) echo "${TVG_ALLOW_START:-08:00}" ;;
    tvguard.main.allow_end) echo "${TVG_ALLOW_END:-21:00}" ;;
    *) exit 1 ;;
esac
SH

cat > "$TMP/bin/date" <<'SH'
#!/bin/sh
case "${1:-}" in
    +%Y-%m-%d) printf '%s\n' "${TVG_DATE:-2026-11-09}" ;;
    +%u) printf '%s\n' "${TVG_WEEKDAY:-1}" ;;
    "+%H %M") printf '%s %s\n' "${TVG_HOUR:-10}" "${TVG_MINUTE:-00}" ;;
    +%s) printf '%s\n' "${TVG_EPOCH:-1800000000}" ;;
    *) echo "unexpected mocked date format: $*" >&2; exit 2 ;;
esac
SH

cat > "$TMP/fw" <<'SH'
#!/bin/sh
case "${1:-}" in
    sync|sync-reply) exit 0 ;;
    gate) printf '%s\n' "$2" > "$TVG_GATE_FILE" ;;
    inspect)
        case "$(cat "$TVG_GATE_FILE")" in
            1) echo blocked ;;
            0) echo allowed ;;
            *) echo unknown ;;
        esac
        ;;
    sample) echo '0 0 0 0 0 0' ;;
    inspect-reply) echo disabled ;;
    sample-reply) echo '0 0 0 0' ;;
    *) exit 2 ;;
esac
SH

cat > "$TMP/data" <<'SH'
#!/bin/sh
case "${1:-root}" in
    root|persistent-root) printf '%s\n' "$TVG_TEST_DATA" ;;
    status) printf 'persistent|%s|mounted\n' "$TVG_TEST_DATA" ;;
    prepare) : ;;
    *) exit 2 ;;
esac
SH

cat > "$TMP/audit" <<'SH'
#!/bin/sh
echo ok
SH

chmod +x "$TMP/bin/uci" "$TMP/bin/date" "$TMP/fw" "$TMP/audit"
echo 0 > "$TMP/gate"
export TVG_GATE_FILE="$TMP/gate"
export TVG_TEST_DATA="$TMP/state"

CTL="$TMP/controller"
python3 - "$ROOT/root/usr/libexec/tvguardctl" "$CTL" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
mapping={
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin': 'PATH='+tmp+'/bin:/usr/bin:/bin',
    'FW=/usr/libexec/tvguard-fw': 'FW='+tmp+'/fw',
    'AUDIT=/usr/libexec/tvguard-isolation-audit': 'AUDIT='+tmp+'/audit',
    'DATA=/usr/libexec/tvguard-data': 'DATA='+tmp+'/data',
    'RUN=/var/run/tvguard.state': 'RUN='+tmp+'/run/runtime',
    'LOCK=/var/run/tvguard.lock': 'LOCK='+tmp+'/run/lock',
}
for before,after in mapping.items():
    assert before in text, before
    text=text.replace(before,after,1)
Path(dst).write_text(text)
PY
chmod 700 "$CTL"

export TVG_ENFORCE=0 TVG_ARMED=0
export TVG_WEEKDAY_MINUTES=60 TVG_WEEKEND_MINUTES=120
export TVG_BONUS_MAX=120 TVG_SILENCE=60
export TVG_ALLOW_START=08:00 TVG_ALLOW_END=21:00
export TVG_DATE=2026-11-09 TVG_WEEKDAY=1 TVG_HOUR=10 TVG_MINUTE=00 TVG_EPOCH=1800000000

reset_state() {
    rm -f "$TMP/run/runtime" "$TMP/state/state" "$TMP/state/events.log"
    rm -rf "$TMP/run/lock"
    echo 0 > "$TMP/gate"
}

status_json() {
    sh "$CTL" status > "$TMP/status.json"
}

assert_json() {
    status_json
    python3 - "$TMP/status.json" "$1" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
exec(sys.argv[2], {"s":s})
PY
}

sync_and_assert() {
    sh "$CTL" sync
    assert_json "$1"
}

# Weekday/weekend quota selection.
reset_state
export TVG_DATE=2026-11-09 TVG_WEEKDAY=1 TVG_HOUR=10 TVG_MINUTE=00 TVG_EPOCH=1800000000
sync_and_assert 'assert s["quota_seconds"] == 3600 and s["policy_reason"] == "none" and s["would_block"] == 0'

reset_state
export TVG_DATE=2026-11-08 TVG_WEEKDAY=7 TVG_EPOCH=1794141600
sync_and_assert 'assert s["quota_seconds"] == 7200 and s["policy_reason"] == "none"'

# Normal daytime window: start inclusive, end exclusive.
reset_state
export TVG_DATE=2026-11-09 TVG_WEEKDAY=1 TVG_ALLOW_START=08:00 TVG_ALLOW_END=21:00
export TVG_HOUR=08 TVG_MINUTE=00 TVG_EPOCH=1800000100
sync_and_assert 'assert s["policy_reason"] == "none" and s["would_block"] == 0'

export TVG_HOUR=20 TVG_MINUTE=59 TVG_EPOCH=1800000200
sync_and_assert 'assert s["policy_reason"] == "none" and s["would_block"] == 0'

export TVG_HOUR=21 TVG_MINUTE=00 TVG_EPOCH=1800000300
sync_and_assert 'assert s["policy_reason"] == "window" and s["would_block"] == 1 and s["blocked"] == 0'

# Overnight window: 20:00 -> 07:00.
reset_state
export TVG_ALLOW_START=20:00 TVG_ALLOW_END=07:00
export TVG_HOUR=19 TVG_MINUTE=59 TVG_EPOCH=1800000400
sync_and_assert 'assert s["policy_reason"] == "window" and s["would_block"] == 1'

export TVG_HOUR=20 TVG_MINUTE=00 TVG_EPOCH=1800000500
sync_and_assert 'assert s["policy_reason"] == "none" and s["would_block"] == 0'

export TVG_HOUR=06 TVG_MINUTE=59 TVG_EPOCH=1800000600
sync_and_assert 'assert s["policy_reason"] == "none" and s["would_block"] == 0'

export TVG_HOUR=07 TVG_MINUTE=00 TVG_EPOCH=1800000700
sync_and_assert 'assert s["policy_reason"] == "window" and s["would_block"] == 1'

# Equal start/end means clock-unrestricted; malformed time safely denies child policy.
reset_state
export TVG_ALLOW_START=00:00 TVG_ALLOW_END=00:00 TVG_HOUR=13 TVG_MINUTE=37 TVG_EPOCH=1800000800
sync_and_assert 'assert s["policy_reason"] == "none"'

reset_state
export TVG_ALLOW_START=25:00 TVG_ALLOW_END=21:00 TVG_HOUR=10 TVG_MINUTE=00 TVG_EPOCH=1800000900
sync_and_assert 'assert s["policy_reason"] == "window" and s["would_block"] == 1'

# Quota exhaustion takes precedence over clock-window explanation.
reset_state
export TVG_ALLOW_START=08:00 TVG_ALLOW_END=21:00 TVG_HOUR=10 TVG_MINUTE=00 TVG_EPOCH=1800001000
sh "$CTL" sync
python3 - "$TMP/run/runtime" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
lines=['USED_S=3600' if line.startswith('USED_S=') else line for line in lines]
p.write_text('\n'.join(lines)+'\n')
PY
sh "$CTL" sync
assert_json 'assert s["used_seconds"] == 3600 and s["remaining_seconds"] == 0 and s["policy_reason"] == "quota" and s["would_block"] == 1'

# Reward boundary: exactly cap is accepted; exceeding cap is rejected; only latest reward is undoable.
reset_state
export TVG_ALLOW_START=00:00 TVG_ALLOW_END=00:00 TVG_EPOCH=1800001100
sh "$CTL" bonus 60
sh "$CTL" bonus 60
assert_json 'assert s["bonus_seconds"] == 7200 and s["bonus_undo_available"] == 1 and s["quota_seconds"] == 10800'
if sh "$CTL" bonus 15 > "$TMP/out" 2>&1; then
    echo "FAIL: bonus exceeded configured daily cap" >&2
    exit 1
fi
grep -q 'daily bonus cap reached' "$TMP/out"
sh "$CTL" bonus undo
assert_json 'assert s["bonus_seconds"] == 3600 and s["bonus_undo_available"] == 0'
if sh "$CTL" bonus undo > "$TMP/out" 2>&1; then
    echo "FAIL: second undo incorrectly rewound an older reward" >&2
    exit 1
fi

# New parent mode persists across runtime loss (restart) and day rollover.
reset_state
export TVG_DATE=2026-11-09 TVG_WEEKDAY=1 TVG_EPOCH=1800001200
sh "$CTL" bonus 30
sh "$CTL" mode parent
assert_json 'assert s["mode"] == "parent" and s["parent_until"] == 0 and s["bonus_seconds"] == 1800'
rm -f "$TMP/run/runtime"
assert_json 'assert s["mode"] == "parent" and s["parent_until"] == 0'

export TVG_DATE=2026-11-10 TVG_WEEKDAY=2 TVG_EPOCH=1800087600
sh "$CTL" sync
assert_json 'assert s["date"] == "2026-11-10" and s["mode"] == "parent" and s["parent_until"] == 0'
assert_json 'assert s["used_seconds"] == 0 and s["bonus_seconds"] == 0 and s["policy_reason"] == "none"'

# Legacy timed-parent migration: future expiry remains temporary; after expiry it becomes child once.
reset_state
export TVG_DATE=2026-11-09 TVG_WEEKDAY=1 TVG_EPOCH=1800002000
sh "$CTL" sync
python3 - "$TMP/run/runtime" "$TMP/state/state" <<'PY'
from pathlib import Path
import sys
for name in sys.argv[1:]:
    p=Path(name)
    lines=p.read_text().splitlines()
    out=[]
    for line in lines:
        if line.startswith('MODE='):
            out.append('MODE=parent')
        elif line.startswith('PARENT_UNTIL='):
            out.append('PARENT_UNTIL=1800002600')
        else:
            out.append(line)
    p.write_text('\n'.join(out)+'\n')
PY
sh "$CTL" sync
assert_json 'assert s["mode"] == "parent" and s["parent_until"] == 1800002600'
export TVG_EPOCH=1800002601
sh "$CTL" sync
assert_json 'assert s["mode"] == "child" and s["parent_until"] == 0'
grep -q 'parent_expired' "$TMP/state/events.log"

# Invalid numeric UCI must fail before state mutation.
reset_state
export TVG_WEEKDAY_MINUTES=oops
if sh "$CTL" sync > "$TMP/out" 2>&1; then
    echo "FAIL: invalid numeric configuration was accepted" >&2
    exit 1
fi
grep -q 'invalid numeric configuration: WEEKDAY' "$TMP/out"
export TVG_WEEKDAY_MINUTES=60

echo "PASS: deterministic quota, schedule, reward, persistent-parent and migration policy unit tests"
