#!/bin/sh
# Host-only smoke test: mocks uci/firewall, never touches host iptables.
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
inspect) if [ "$(cat "$TVGUARD_TEST_GATE")" = 1 ]; then echo blocked; else echo allowed; fi ;;
count) cat "$TVGUARD_TEST_COUNTER" ;;
*) exit 2 ;;
esac
EOFW
chmod +x "$TMP/bin/uci" "$TMP/fw"
echo 0 > "$TMP/counter"
echo 9 > "$TMP/gate"
export TVGUARD_RUN="$TMP/run/runtime"
export TVGUARD_DIR="$TMP/state"
export TVGUARD_LOCK="$TMP/run/lock"
export TVGUARD_FW="$TMP/fw"
export TVGUARD_TEST_COUNTER="$TMP/counter"
export TVGUARD_TEST_GATE="$TMP/gate"
PATH="$TMP/bin:$PATH"
export PATH
CTL="$ROOT/root/usr/libexec/tvguardctl"
sh "$CTL" sync
sh "$CTL" status > "$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["enforce"] == 0
assert s["mode"] == "child"
assert s["bonus_seconds"] == 0
PY
sh "$CTL" bonus 15
sh "$CTL" status > "$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["bonus_seconds"] == 900, s
assert s["remaining_seconds"] >= 900, s
PY
sh "$CTL" bonus undo
sh "$CTL" status > "$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))["bonus_seconds"] == 0
PY
sh "$CTL" mode parent 30
sh "$CTL" status > "$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["mode"] == "parent"
assert s["parent_until"] > 0
PY
sh "$CTL" mode locked
sh "$CTL" status > "$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["mode"] == "locked" and s["would_block"] == 1
assert s["enforce"] == 0 and s["blocked"] == 0
PY
sh "$CTL" mode child
echo 100 > "$TMP/counter"
sh "$CTL" tick
sh "$CTL" status > "$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["used_seconds"] > 0, s
assert s["activity"] == "active", s
assert s["enforce"] == 0, s
PY
if sh "$CTL" enforce on > "$TMP/out" 2>&1; then
    echo "FAIL: observer-only build allowed enforcement without arming" >&2
    exit 1
fi
test "$(cat "$TMP/gate")" = 0
echo "PASS: status, award/undo, parent/lock, activity, enforcement interlock"
