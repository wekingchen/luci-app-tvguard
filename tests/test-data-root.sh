#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/mmc" "$TMP/etc" "$TMP/run"
MOUNTS="$TMP/mounts"
: > "$MOUNTS"

SRC="$ROOT/root/usr/libexec/tvguard-data"
DST="$TMP/data"
python3 - "$SRC" "$DST" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
s=Path(src).read_text()
s=s.replace('PERSIST_MOUNT=/mnt/mmcblk2p4','PERSIST_MOUNT='+tmp+'/mmc',1)
s=s.replace('LEGACY_DIR=/etc/tvguard','LEGACY_DIR='+tmp+'/etc/tvguard',1)
s=s.replace('VOLATILE_DIR=/var/run/tvguard-data','VOLATILE_DIR='+tmp+'/run/tvguard-data',1)
s=s.replace('MOUNTS=/proc/mounts','MOUNTS='+tmp+'/mounts',1)
Path(dst).write_text(s)
PY
chmod +x "$DST"

# Without the persistent mount, never choose /etc as writable DB.
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
mkdir -p "$TMP/etc/tvguard"
printf 'legacy-state\n' > "$TMP/etc/tvguard/state"
printf 'legacy-event\n' > "$TMP/etc/tvguard/events.log"
sh "$DST" prepare
[ -f "$TMP/run/tvguard-data/state" ]
[ -f "$TMP/etc/tvguard/state" ]

# Mount appears: legacy data migrates to durable store and fallback merges.
printf 'volatile-event\n' >> "$TMP/run/tvguard-data/events.log"
printf '/dev/mmcblk2p4 %s ext4 rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" prepare
[ "$(sh "$DST" root)" = "$TMP/mmc/tvguard" ]
grep -q 'legacy-state' "$TMP/mmc/tvguard/state"
grep -q 'legacy-event' "$TMP/mmc/tvguard/events.log"
[ "$(grep -c '^legacy-event
[ -f "$TMP/mmc/tvguard/.layout-v1" ]

# After successful migration the known legacy files are removed. If the
# directory becomes empty, a compatibility symlink may replace it.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
fi

# A later mount outage selects only volatile RAM, never overlay /etc.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

echo 'PASS: durable data migrates to mmc and mount outage falls back only to volatile RAM'
 "$TMP/mmc/tvguard/events.log")" -eq 1 ]
grep -q 'volatile-event' "$TMP/mmc/tvguard/events.log"
[ -f "$TMP/mmc/tvguard/.layout-v1" ]

# After successful migration the known legacy files are removed. If the
# directory becomes empty, a compatibility symlink may replace it.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
fi

# A later mount outage selects only volatile RAM, never overlay /etc.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

echo 'PASS: durable data migrates to mmc and mount outage falls back only to volatile RAM'
