#!/bin/sh
# Unit-test OpenWrt init/procd behavior without an OpenWrt host.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
LOG="$TMP/log"
: > "$LOG"

cat > "$TMP/ctl" <<'SH'
#!/bin/sh
printf 'ctl:%s\n' "$*" >> "$TVG_INIT_LOG"
exit "${TVG_CTL_EXIT:-0}"
SH

cat > "$TMP/data" <<'SH'
#!/bin/sh
printf 'data:%s\n' "$*" >> "$TVG_INIT_LOG"
case "${1:-}" in
    prepare) exit "${TVG_DATA_PREPARE_EXIT:-0}" ;;
    config-sync) exit "${TVG_DATA_CONFIG_EXIT:-0}" ;;
    *) exit 0 ;;
esac
SH

cat > "$TMP/logger" <<'SH'
#!/bin/sh
printf 'logger:%s\n' "$*" >> "$TVG_INIT_LOG"
exit 0
SH

cat > "$TMP/daemon" <<'SH'
#!/bin/sh
exit 0
SH

chmod +x "$TMP/ctl" "$TMP/data" "$TMP/logger" "$TMP/daemon"
export TVG_INIT_LOG="$LOG"
export TVG_CTL_EXIT=0
export TVG_DATA_PREPARE_EXIT=0
export TVG_DATA_CONFIG_EXIT=0

INIT="$TMP/init"
python3 - "$ROOT/root/etc/init.d/tvguard" "$INIT" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
text=text.replace('/usr/libexec/tvguardctl', tmp+'/ctl')
text=text.replace('/usr/libexec/tvguard-data', tmp+'/data')
text=text.replace('/usr/libexec/tvguardd', tmp+'/daemon')
text=text.replace('logger -t tvguard', tmp+'/logger -t tvguard')
Path(dst).write_text(text)
PY

cat > "$TMP/harness" <<'SH'
#!/bin/sh
set -eu
LOG="$TVG_INIT_LOG"

procd_open_instance() { echo 'procd:open' >> "$LOG"; }
procd_set_param() { printf 'procd:param:%s\n' "$*" >> "$LOG"; }
procd_close_instance() { echo 'procd:close' >> "$LOG"; }
procd_add_reload_trigger() { printf 'procd:trigger:%s\n' "$*" >> "$LOG"; }

. "$TVG_INIT_SCRIPT"

case "$1" in
    start) start_service ;;
    reload) reload_service ;;
    triggers) service_triggers ;;
    stop) stop_service ;;
    *) exit 2 ;;
esac
SH
chmod +x "$TMP/harness"
export TVG_INIT_SCRIPT="$INIT"

# Start: durable-data prepare, config persistence sync and controller sync run
# before procd launches the daemon.
: > "$LOG"
sh "$TMP/harness" start
grep -qx 'data:prepare' "$LOG"
grep -qx 'data:config-sync' "$LOG"
grep -qx 'ctl:sync' "$LOG"
grep -qx 'procd:open' "$LOG"
grep -qx "procd:param:command $TMP/daemon" "$LOG"
grep -qx 'procd:param:respawn 3600 5 5' "$LOG"
grep -qx 'procd:close' "$LOG"
! grep -q 'firewall' "$LOG"

# Failed durable-data preparation aborts before config/controller sync and
# before procd starts the daemon.
: > "$LOG"
export TVG_DATA_PREPARE_EXIT=7
if sh "$TMP/harness" start >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: start_service ignored durable-data prepare failure" >&2
    exit 1
fi
grep -qx 'data:prepare' "$LOG"
! grep -q '^data:config-sync$' "$LOG"
! grep -q '^ctl:sync$' "$LOG"
! grep -q '^procd:' "$LOG"
export TVG_DATA_PREPARE_EXIT=0

# Config backup failure is logged but does not stop a safe live config from
# starting; controller sync still gates actual policy.
: > "$LOG"
export TVG_DATA_CONFIG_EXIT=9
sh "$TMP/harness" start
grep -qx 'data:prepare' "$LOG"
grep -qx 'data:config-sync' "$LOG"
grep -q '^logger:-t tvguard UCI config persistence sync failed;' "$LOG"
grep -qx 'ctl:sync' "$LOG"
grep -qx 'procd:open' "$LOG"
export TVG_DATA_CONFIG_EXIT=0

# Failed controller sync aborts before procd.
: > "$LOG"
export TVG_CTL_EXIT=7
if sh "$TMP/harness" start >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: start_service ignored controller sync failure" >&2
    exit 1
fi
grep -qx 'data:prepare' "$LOG"
grep -qx 'data:config-sync' "$LOG"
grep -qx 'ctl:sync' "$LOG"
! grep -q '^procd:' "$LOG"
export TVG_CTL_EXIT=0

# Reload persists committed UCI changes, then syncs only TV Guard state/rules.
: > "$LOG"
sh "$TMP/harness" reload
grep -qx 'data:config-sync' "$LOG"
grep -qx 'ctl:sync' "$LOG"
[ "$(wc -l < "$LOG")" -eq 2 ]

# Trigger subscription stays TV Guard-only.
: > "$LOG"
sh "$TMP/harness" triggers
[ "$(cat "$LOG")" = 'procd:trigger:tvguard' ]

# Stop remains policy-neutral.
: > "$LOG"
sh "$TMP/harness" stop
[ ! -s "$LOG" ]

echo "PASS: procd lifecycle includes durable UCI sync and stays proxy-neutral"
