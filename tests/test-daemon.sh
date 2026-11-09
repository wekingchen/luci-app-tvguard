#!/bin/sh
# Unit-test one daemon iteration; no real sleep, controller or logger.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
LOG="$TMP/log"
: > "$LOG"

cat > "$TMP/ctl" <<'SH'
#!/bin/sh
printf 'ctl:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit "${TVG_TICK_EXIT:-0}"
SH

cat > "$TMP/data" <<'SH'
#!/bin/sh
printf 'data:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit "${TVG_DATA_EXIT:-0}"
SH

cat > "$TMP/retention" <<'SH'
#!/bin/sh
printf 'retention:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit "${TVG_RETENTION_EXIT:-0}"
SH

cat > "$TMP/logger" <<'SH'
#!/bin/sh
printf 'logger:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit 0
SH

cat > "$TMP/sleep" <<'SH'
#!/bin/sh
printf 'sleep:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit 0
SH

chmod +x "$TMP/ctl" "$TMP/data" "$TMP/retention" "$TMP/logger" "$TMP/sleep"
export TVG_DAEMON_LOG="$LOG"
export TVG_DATA_EXIT=0
export TVG_RETENTION_EXIT=0

DAEMON="$TMP/daemon"
python3 - "$ROOT/root/usr/libexec/tvguardd" "$DAEMON" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
text=text.replace('/usr/libexec/tvguardctl', tmp+'/ctl')
text=text.replace('/usr/libexec/tvguard-data', tmp+'/data')
text=text.replace('/usr/libexec/tvguard-retention', tmp+'/retention')
text=text.replace('logger -t tvguard', tmp+'/logger -t tvguard')
text=text.replace('sleep 10', tmp+'/sleep 10')
# Execute exactly one production loop body.
text=text.replace('while :; do', 'for _tvg_once in 1; do', 1)
Path(dst).write_text(text)
PY
chmod +x "$DAEMON"

# Successful tick: startup + loop prepare happen, retention trims once, and
# no error logger is emitted.
export TVG_TICK_EXIT=0
: > "$LOG"
sh "$DAEMON"
[ "$(grep -c '^data:prepare$' "$LOG")" -eq 2 ]
grep -q '^retention:trim$' "$LOG"
grep -q '^ctl:tick$' "$LOG"
grep -q '^sleep:10$' "$LOG"
! grep -q '^logger:' "$LOG"

# Failed tick: log only; daemon loop still reaches the normal sleep.
export TVG_TICK_EXIT=7
: > "$LOG"
sh "$DAEMON"
grep -q '^ctl:tick$' "$LOG"
grep -q '^logger:-t tvguard sample/update failed; keeping existing firewall gate$' "$LOG"
grep -q '^sleep:10$' "$LOG"

# A transient data-prepare failure is logged but does not stop the daemon from
# running the tick against the currently selected safe root.
export TVG_TICK_EXIT=0
export TVG_DATA_EXIT=7
: > "$LOG"
sh "$DAEMON"
grep -q '^logger:-t tvguard durable data prepare failed;' "$LOG"
grep -q '^ctl:tick$' "$LOG"
grep -q '^sleep:10$' "$LOG"

echo "PASS: daemon prepares durable data, logs failures and preserves 10-second cadence"
