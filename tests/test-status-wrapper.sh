#!/bin/sh
# Verify the LuCI read wrapper exposes only fixed, read-only commands.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
LOG="$TMP/log"
: > "$LOG"

cat > "$TMP/ctl" <<'SH'
#!/bin/sh
printf 'ctl:%s\n' "$*" >> "$TVG_WRAPPER_LOG"
exit 0
SH

cat > "$TMP/retention" <<'SH'
#!/bin/sh
printf 'retention:%s\n' "$*" >> "$TVG_WRAPPER_LOG"
exit 0
SH

cat > "$TMP/soak-report" <<'SH'
#!/bin/sh
printf 'soak-report:%s\n' "$*" >> "$TVG_WRAPPER_LOG"
exit 0
SH

cat > "$TMP/audit" <<'SH'
#!/bin/sh
printf 'audit:%s\n' "$*" >> "$TVG_WRAPPER_LOG"
exit 0
SH
chmod +x "$TMP/ctl" "$TMP/audit" "$TMP/retention" "$TMP/soak-report"
export TVG_WRAPPER_LOG="$LOG"

WRAPPER="$TMP/wrapper"
python3 - "$ROOT/root/usr/libexec/tvguard-status" "$WRAPPER" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
text=text.replace('/usr/libexec/tvguardctl', tmp+'/ctl')
text=text.replace('/usr/libexec/tvguard-isolation-audit', tmp+'/audit')
text=text.replace('/usr/libexec/tvguard-retention', tmp+'/retention')
text=text.replace('/usr/libexec/tvguard-soak-report', tmp+'/soak-report')
Path(dst).write_text(text)
PY
chmod +x "$WRAPPER"

run_expect() {
    expected="$1"; shift
    : > "$LOG"
    sh "$WRAPPER" "$@"
    [ "$(cat "$LOG")" = "$expected" ] || {
        echo "FAIL: expected '$expected', got '$(cat "$LOG")'" >&2
        exit 1
    }
}

run_expect 'ctl:status'
run_expect 'ctl:status' status
run_expect 'ctl:brief' brief
run_expect 'ctl:evidence' evidence
run_expect 'ctl:log' log
run_expect 'ctl:calibration' calibration
run_expect 'ctl:calibration-v4' calibration-v4
run_expect 'ctl:calibration-v5' calibration-v5
run_expect 'ctl:learning' learning
run_expect 'retention:report' storage
run_expect 'soak-report:' soak
run_expect 'audit:' isolation

# Extra arguments must never be forwarded to the underlying reader.
run_expect 'ctl:status' status 'bonus' '60'
run_expect 'audit:' isolation '--anything'

# Unknown commands are rejected and execute nothing.
: > "$LOG"
if sh "$WRAPPER" enforce on >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: read wrapper accepted mutating command" >&2
    exit 1
fi
[ ! -s "$LOG" ]

: > "$LOG"
if sh "$WRAPPER" '../../bin/sh' >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: read wrapper accepted arbitrary command" >&2
    exit 1
fi
[ ! -s "$LOG" ]

echo "PASS: LuCI read wrapper exposes only fixed status/brief/evidence/log/calibration-v4/v5/learning/storage/soak/isolation readers"
