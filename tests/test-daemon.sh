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
case "${1:-}" in
    prepare) exit "${TVG_DATA_PREPARE_EXIT:-0}" ;;
    config-sync) exit "${TVG_DATA_CONFIG_EXIT:-0}" ;;
    *) exit 0 ;;
esac
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

cat > "$TMP/report" <<'SH'
#!/bin/sh
printf 'report:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit 0
SH

cat > "$TMP/sleep" <<'SH'
#!/bin/sh
printf 'sleep:%s\n' "$*" >> "$TVG_DAEMON_LOG"
exit 0
SH

chmod +x "$TMP/ctl" "$TMP/data" "$TMP/retention" "$TMP/logger" "$TMP/report" "$TMP/sleep"
export TVG_DAEMON_LOG="$LOG"
export TVG_DATA_PREPARE_EXIT=0
export TVG_DATA_CONFIG_EXIT=0
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
text=text.replace('/usr/libexec/tvguard-daily-report', tmp+'/report')
text=text.replace('logger -t tvguard', tmp+'/logger -t tvguard')
text=text.replace('sleep 10', tmp+'/sleep 10')
text=text.replace('while :; do', 'for _tvg_once in 1; do', 1)
Path(dst).write_text(text)
PY
chmod +x "$DAEMON"

# Successful iteration: prepare/config-sync happen at startup and in-loop,
# retention trims once, tick runs once, no errors are logged.
export TVG_TICK_EXIT=0
: > "$LOG"
sh "$DAEMON"
[ "$(grep -c '^data:prepare$' "$LOG")" -eq 2 ]
[ "$(grep -c '^data:config-sync$' "$LOG")" -eq 2 ]
[ "$(grep -c '^retention:trim$' "$LOG")" -eq 1 ]
[ "$(grep -c '^ctl:tick$' "$LOG")" -eq 1 ]
grep -qx 'report:tick' "$LOG"
grep -qx 'sleep:10' "$LOG"
! grep -q '^logger:' "$LOG"

# Tick failure is logged; cadence continues.
export TVG_TICK_EXIT=7
: > "$LOG"
sh "$DAEMON"
grep -qx 'ctl:tick' "$LOG"
! grep -q '^report:' "$LOG"
grep -qx 'logger:-t tvguard sample/update failed; keeping existing firewall gate' "$LOG"
grep -qx 'sleep:10' "$LOG"

# Transient mmc prepare failure is logged but does not stop the safe current
# root from being used for config sync/tick.
export TVG_TICK_EXIT=0
export TVG_DATA_PREPARE_EXIT=7
: > "$LOG"
sh "$DAEMON"
grep -q '^logger:-t tvguard durable data prepare failed;' "$LOG"
grep -q '^data:config-sync$' "$LOG"
grep -qx 'ctl:tick' "$LOG"
grep -qx 'sleep:10' "$LOG"
export TVG_DATA_PREPARE_EXIT=0

# Config backup failure is diagnostic only and never changes firewall cadence.
export TVG_DATA_CONFIG_EXIT=9
: > "$LOG"
sh "$DAEMON"
grep -q '^logger:-t tvguard UCI config persistence sync failed;' "$LOG"
grep -qx 'ctl:tick' "$LOG"
grep -qx 'sleep:10' "$LOG"

echo "PASS: daemon maintains bounded data/config persistence and 10-second cadence"
