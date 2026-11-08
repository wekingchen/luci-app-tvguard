#!/bin/sh
# Unit-test tvguard-fw policy() without touching host iptables.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin"

cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
[ "${1:-}" = get ] || exit 2
case "${2:-}" in
    tvguard.main.enforce) echo "${TVG_FW_ENFORCE:-0}" ;;
    tvguard.main.allow_enforcement) echo "${TVG_FW_ARMED:-0}" ;;
    tvguard.main.observe_reply) echo 0 ;;
    tvguard.main.ip) echo 192.168.101.76 ;;
    tvguard.main.interface) echo br-lan ;;
    *) exit 1 ;;
esac
SH

cat > "$TMP/bin/date" <<'SH'
#!/bin/sh
[ "${1:-}" = +%s ] || exit 2
echo "${TVG_FW_NOW:-1800000000}"
SH
chmod +x "$TMP/bin/uci" "$TMP/bin/date"

POLICY="$TMP/policy"
python3 - "$ROOT/root/usr/libexec/tvguard-fw" "$POLICY" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
marker='case "${1:-}" in'
idx=text.find(marker)
assert idx > 0, "dispatch marker missing"
prefix=text[:idx]
prefix=prefix.replace(
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin',
    'PATH='+tmp+'/bin:/usr/bin:/bin',
    1
)
prefix=prefix.replace(
    'FILE=/etc/tvguard/state',
    'FILE='+tmp+'/state',
    1
)
Path(dst).write_text(prefix + '\npolicy\n')
PY
chmod +x "$POLICY"

export TVG_FW_NOW=1800000000
export TVG_FW_ENFORCE=0 TVG_FW_ARMED=0

write_state() {
    cat > "$TMP/state" <<EOF
MODE=$1
BLOCKED=$2
PARENT_UNTIL=$3
EOF
}

expect_policy() {
    expected="$1"
    actual="$(sh "$POLICY")"
    [ "$actual" = "$expected" ] || {
        echo "FAIL: expected policy=$expected, got $actual" >&2
        cat "$TMP/state" 2>/dev/null || :
        exit 1
    }
}

# Two-key safety interlock always fails open when formal control is not armed.
rm -f "$TMP/state"
export TVG_FW_ENFORCE=0 TVG_FW_ARMED=0
expect_policy 0
export TVG_FW_ENFORCE=1 TVG_FW_ARMED=0
expect_policy 0

# Once both keys are on, missing/corrupt state must fail closed.
export TVG_FW_ENFORCE=1 TVG_FW_ARMED=1
rm -f "$TMP/state"
expect_policy 1

write_state locked 0 0
expect_policy 1

write_state child 0 0
expect_policy 0
write_state child 1 0
expect_policy 1
write_state child broken 0
expect_policy 1

# v0.1.7 persistent parent mode is explicitly represented by zero expiry.
write_state parent 0 0
expect_policy 0

# Positive parent expiry is migration-only: future allows, expired blocks until
# controller converts the old state back to child.
write_state parent 0 1800000600
expect_policy 0
write_state parent 0 1799999999
expect_policy 1

write_state parent 0 broken
expect_policy 1
write_state unexpected 0 0
expect_policy 1

echo "PASS: firewall reload policy handles persistent parent, legacy timers and fail-closed state safely"
