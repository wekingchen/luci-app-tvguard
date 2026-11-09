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
for old,new in (
    ('PERSIST_MOUNT=/mnt/mmcblk2p4','PERSIST_MOUNT='+tmp+'/mmc'),
    ('LEGACY_DIR=/etc/tvguard','LEGACY_DIR='+tmp+'/etc/tvguard'),
    ('VOLATILE_DIR=/var/run/tvguard-data','VOLATILE_DIR='+tmp+'/run/tvguard-data'),
    ('MOUNTS=/proc/mounts','MOUNTS='+tmp+'/mounts'),
):
    assert old in s, old
    s=s.replace(old,new,1)
Path(dst).write_text(s)
PY
chmod +x "$DST"

# 1) Persistent mount absent: runtime must use RAM, never /etc as writable DB.
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
mkdir -p "$TMP/etc/tvguard"
printf 'legacy-state\n' > "$TMP/etc/tvguard/state"
printf 'legacy-event\n' > "$TMP/etc/tvguard/events.log"
printf 'legacy-session\n' > "$TMP/etc/tvguard/learning-sessions.csv"

sh "$DST" prepare
[ -f "$TMP/run/tvguard-data/state" ]
[ -f "$TMP/run/tvguard-data/events.log" ]
[ -f "$TMP/run/tvguard-data/learning-sessions.csv" ]
[ -f "$TMP/etc/tvguard/state" ]

# Simulate new records created only during the outage.
printf 'volatile-event\n' >> "$TMP/run/tvguard-data/events.log"
printf 'volatile-session\n' >> "$TMP/run/tvguard-data/learning-sessions.csv"

# 2) Persistent mount appears: legacy data migrates to mmc, outage-only suffix
# merges once, and the seeded legacy prefix must not be duplicated.
printf '/dev/mmcblk2p4 %s ext4 rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" prepare

[ "$(sh "$DST" root)" = "$TMP/mmc/tvguard" ]
[ -f "$TMP/mmc/tvguard/.layout-v1" ]
grep -q '^legacy-state$' "$TMP/mmc/tvguard/state"
grep -q '^legacy-event$' "$TMP/mmc/tvguard/events.log"
grep -q '^volatile-event$' "$TMP/mmc/tvguard/events.log"
grep -q '^legacy-session$' "$TMP/mmc/tvguard/learning-sessions.csv"
grep -q '^volatile-session$' "$TMP/mmc/tvguard/learning-sessions.csv"
[ "$(grep -c '^legacy-event$' "$TMP/mmc/tvguard/events.log")" -eq 1 ]
[ "$(grep -c '^legacy-session$' "$TMP/mmc/tvguard/learning-sessions.csv")" -eq 1 ]

# Known legacy files are removed only after verified migration. If the legacy
# directory becomes empty it may become a compatibility symlink.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
    [ ! -e "$TMP/etc/tvguard/events.log" ]
    [ ! -e "$TMP/etc/tvguard/learning-sessions.csv" ]
fi

# 3) A later mount outage selects only volatile RAM, never overlay /etc.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

echo 'PASS: durable data migrates to mmc, avoids duplicate learning data and uses RAM-only fallback'
