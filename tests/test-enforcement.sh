#!/bin/sh
# Deterministic formal-enforcement state-machine test. Never touches host firewall.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/run"

echo 0 > "$TMP/uci.enforce"
echo 0 > "$TMP/uci.armed"
: > "$TMP/uci.log"

cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
cmd="${1:-}"; shift || :
case "$cmd" in
    get)
        case "${1:-}" in
            tvguard.main.enforce) cat "$TVG_UCI_ENFORCE" ;;
            tvguard.main.allow_enforcement) cat "$TVG_UCI_ARMED" ;;
            tvguard.main.weekday_minutes) echo 60 ;;
            tvguard.main.weekend_minutes) echo 120 ;;
            tvguard.main.max_bonus_minutes) echo 120 ;;
            tvguard.main.silence_seconds) echo 60 ;;
            tvguard.main.allow_start|tvguard.main.allow_end) echo 00:00 ;;
            *) exit 1 ;;
        esac
        ;;
    set)
        case "${1:-}" in
            tvguard.main.enforce=*)
                value="${1#*=}"
                value="$(printf '%s' "$value" | tr -d "'")"
                printf '%s\n' "$value" > "$TVG_UCI_ENFORCE"
                printf 'set enforce=%s\n' "$value" >> "$TVG_UCI_LOG"
                ;;
            *) exit 2 ;;
        esac
        ;;
    commit)
        [ "${1:-}" = tvguard ] || exit 2
        echo commit >> "$TVG_UCI_LOG"
        ;;
    *) exit 2 ;;
esac
SH

cat > "$TMP/fw" <<'SH'
#!/bin/sh
case "${1:-}" in
    sync) exit 0 ;;
    gate)
        printf '%s\n' "$2" > "$TVG_GATE_FILE"
        printf 'gate=%s\n' "$2" >> "$TVG_GATE_LOG"
        ;;
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
    sync-reply) exit 0 ;;
    *) exit 2 ;;
esac
SH

cat > "$TMP/audit" <<'SH'
#!/bin/sh
printf '%s\n' "${TVG_AUDIT_STATE:-ok}"
[ "${TVG_AUDIT_STATE:-ok}" = ok ]
SH

chmod +x "$TMP/bin/uci" "$TMP/fw" "$TMP/audit"
echo 0 > "$TMP/gate"
: > "$TMP/gate.log"

export TVG_UCI_ENFORCE="$TMP/uci.enforce"
export TVG_UCI_ARMED="$TMP/uci.armed"
export TVG_UCI_LOG="$TMP/uci.log"
export TVG_GATE_FILE="$TMP/gate"
export TVG_GATE_LOG="$TMP/gate.log"
export TVG_AUDIT_STATE=ok

CTL="$TMP/controller"
python3 - "$ROOT/root/usr/libexec/tvguardctl" "$CTL" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
mapping={
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin':'PATH='+tmp+'/bin:/usr/bin:/bin',
    'FW=/usr/libexec/tvguard-fw':'FW='+tmp+'/fw',
    'AUDIT=/usr/libexec/tvguard-isolation-audit':'AUDIT='+tmp+'/audit',
    'RUN=/var/run/tvguard.state':'RUN='+tmp+'/run/runtime',
    'DIR=/etc/tvguard':'DIR='+tmp+'/state',
    'LOCK=/var/run/tvguard.lock':'LOCK='+tmp+'/run/lock',
}
for before,after in mapping.items():
    assert before in text, before
    text=text.replace(before,after,1)
Path(dst).write_text(text)
PY
chmod 700 "$CTL"

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

# Default: formal control cannot turn on without the admin key.
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then
    echo "FAIL: enforcement enabled without admin interlock" >&2
    exit 1
fi
grep -q 'allow_enforcement=1' "$TMP/out"
[ "$(cat "$TMP/uci.enforce")" = 0 ]
[ "$(cat "$TMP/gate")" = 0 ]

# Armed but unsafe/unavailable isolation still refuses without UCI/gate mutation.
echo 1 > "$TMP/uci.armed"
export TVG_AUDIT_STATE='unsafe:test'
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then
    echo "FAIL: unsafe isolation enabled enforcement" >&2
    exit 1
fi
grep -q 'proxy isolation audit is not ok' "$TMP/out"
[ "$(cat "$TMP/uci.enforce")" = 0 ]
[ "$(cat "$TMP/gate")" = 0 ]

export TVG_AUDIT_STATE='unavailable:raw_table'
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then
    echo "FAIL: unavailable isolation enabled enforcement" >&2
    exit 1
fi
[ "$(cat "$TMP/uci.enforce")" = 0 ]

# Exact live audit=ok + armed key is the only successful path.
export TVG_AUDIT_STATE=ok
sh "$CTL" enforce on
[ "$(cat "$TMP/uci.enforce")" = 1 ]
grep -q '^set enforce=1$' "$TMP/uci.log"
grep -q '^commit$' "$TMP/uci.log"
assert_json 'assert s["enforce"] == 1 and s["armed"] == 1 and s["mode"] == "child"'
assert_json 'assert s["firewall_state"] == "allowed" and s["blocked"] == 0'

# Formal control: lock -> DROP; persistent parent -> RETURN; child -> RETURN.
sh "$CTL" mode locked
[ "$(cat "$TMP/gate")" = 1 ]
assert_json 'assert s["mode"] == "locked" and s["would_block"] == 1 and s["blocked"] == 1'

sh "$CTL" mode parent
[ "$(cat "$TMP/gate")" = 0 ]
assert_json 'assert s["mode"] == "parent" and s["parent_until"] == 0 and s["would_block"] == 0 and s["blocked"] == 0'

sh "$CTL" mode child
[ "$(cat "$TMP/gate")" = 0 ]
assert_json 'assert s["mode"] == "child" and s["would_block"] == 0 and s["blocked"] == 0'

# Turning formal control off must restore RETURN even if desired policy is locked.
sh "$CTL" mode locked
[ "$(cat "$TMP/gate")" = 1 ]
sh "$CTL" enforce off
[ "$(cat "$TMP/uci.enforce")" = 0 ]
[ "$(cat "$TMP/gate")" = 0 ]
assert_json 'assert s["enforce"] == 0 and s["mode"] == "locked" and s["would_block"] == 1 and s["blocked"] == 0'

# Missing persistent state while formal control is configured must recover to a
# locked state before persistence. Firewall policy unit tests separately prove
# that locked state maps to DROP during a real fw sync.
rm -f "$TMP/run/runtime" "$TMP/state/state" "$TMP/state/events.log"
echo 1 > "$TMP/uci.enforce"
echo 1 > "$TMP/uci.armed"
echo 0 > "$TMP/gate"
sh "$CTL" sync
assert_json 'assert s["enforce"] == 1 and s["armed"] == 1 and s["mode"] == "locked" and s["would_block"] == 1'
grep -q 'recovery_lock' "$TMP/state/events.log"

# Corrupt persisted MODE is normalized to locked, never child/parent.
rm -f "$TMP/run/runtime"
python3 - "$TMP/state/state" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
lines=['MODE=corrupt' if line.startswith('MODE=') else line for line in lines]
p.write_text('\n'.join(lines)+'\n')
PY
assert_json 'assert s["mode"] == "locked"'

echo "PASS: formal enforcement interlocks, gate transitions and fail-closed recovery state"
