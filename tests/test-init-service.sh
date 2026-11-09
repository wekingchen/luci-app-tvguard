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
exit "${TVG_DATA_EXIT:-0}"
SH
cat > "$TMP/daemon" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/ctl" "$TMP/data" "$TMP/daemon"
export TVG_INIT_LOG="$LOG"
export TVG_CTL_EXIT=0

INIT="$TMP/init"
python3 - "$ROOT/root/etc/init.d/tvguard" "$INIT" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
text=Path(src).read_text()
text=text.replace('/usr/libexec/tvguardctl', tmp+'/ctl')
text=text.replace('/usr/libexec/tvguard-data', tmp+'/data')
text=text.replace('/usr/libexec/tvguardd', tmp+'/daemon')
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

# Start: sync must succeed before daemon/procd instance is created.
: > "$LOG"
sh "$TMP/harness" start
grep -q '^data:prepare
grep -q '^procd:open$' "$LOG"
grep -q "^procd:param:command $TMP/daemon$" "$LOG"
grep -q '^procd:param:respawn 3600 5 5$' "$LOG"
grep -q '^procd:close$' "$LOG"
! grep -q 'firewall' "$LOG"

# Failed initial sync must abort before procd starts the daemon.
: > "$LOG"
export TVG_CTL_EXIT=7
if sh "$TMP/harness" start >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: start_service ignored controller sync failure" >&2
    exit 1
fi
grep -q '^ctl:sync$' "$LOG"
! grep -q '^procd:' "$LOG"
export TVG_CTL_EXIT=0

# Reload: only sync TV Guard state/rules; do not restart/open daemon instance.
: > "$LOG"
sh "$TMP/harness" reload
[ "$(cat "$LOG")" = 'ctl:sync' ]

# Trigger subscription must be TV Guard-only, never global firewall.
: > "$LOG"
sh "$TMP/harness" triggers
[ "$(cat "$LOG")" = 'procd:trigger:tvguard' ]

# Stop is intentionally policy-neutral and performs no firewall/global action.
: > "$LOG"
sh "$TMP/harness" stop
[ ! -s "$LOG" ]

echo "PASS: procd start/reload/trigger lifecycle stays TV Guard-local and proxy-neutral"
 "$LOG"
grep -q '^ctl:sync
grep -q '^procd:open$' "$LOG"
grep -q "^procd:param:command $TMP/daemon$" "$LOG"
grep -q '^procd:param:respawn 3600 5 5$' "$LOG"
grep -q '^procd:close$' "$LOG"
! grep -q 'firewall' "$LOG"

# Failed initial sync must abort before procd starts the daemon.
: > "$LOG"
export TVG_CTL_EXIT=7
if sh "$TMP/harness" start >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: start_service ignored controller sync failure" >&2
    exit 1
fi
grep -q '^ctl:sync$' "$LOG"
! grep -q '^procd:' "$LOG"
export TVG_CTL_EXIT=0

# Reload: only sync TV Guard state/rules; do not restart/open daemon instance.
: > "$LOG"
sh "$TMP/harness" reload
[ "$(cat "$LOG")" = 'ctl:sync' ]

# Trigger subscription must be TV Guard-only, never global firewall.
: > "$LOG"
sh "$TMP/harness" triggers
[ "$(cat "$LOG")" = 'procd:trigger:tvguard' ]

# Stop is intentionally policy-neutral and performs no firewall/global action.
: > "$LOG"
sh "$TMP/harness" stop
[ ! -s "$LOG" ]

echo "PASS: procd start/reload/trigger lifecycle stays TV Guard-local and proxy-neutral"
 "$LOG"
grep -q '^procd:open$' "$LOG"
grep -q "^procd:param:command $TMP/daemon$" "$LOG"
grep -q '^procd:param:respawn 3600 5 5$' "$LOG"
grep -q '^procd:close$' "$LOG"
! grep -q 'firewall' "$LOG"

# Failed initial sync must abort before procd starts the daemon.
: > "$LOG"
export TVG_CTL_EXIT=7
if sh "$TMP/harness" start >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: start_service ignored controller sync failure" >&2
    exit 1
fi
grep -q '^ctl:sync$' "$LOG"
! grep -q '^procd:' "$LOG"
export TVG_CTL_EXIT=0

# Reload: only sync TV Guard state/rules; do not restart/open daemon instance.
: > "$LOG"
sh "$TMP/harness" reload
[ "$(cat "$LOG")" = 'ctl:sync' ]

# Trigger subscription must be TV Guard-only, never global firewall.
: > "$LOG"
sh "$TMP/harness" triggers
[ "$(cat "$LOG")" = 'procd:trigger:tvguard' ]

# Stop is intentionally policy-neutral and performs no firewall/global action.
: > "$LOG"
sh "$TMP/harness" stop
[ ! -s "$LOG" ]

echo "PASS: procd start/reload/trigger lifecycle stays TV Guard-local and proxy-neutral"
