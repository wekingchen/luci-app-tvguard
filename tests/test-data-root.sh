#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

mkdir -p "$TMP/mmc" "$TMP/etc/config" "$TMP/run"
MOUNTS="$TMP/mounts"
: > "$MOUNTS"
printf 'default-config\n' > "$TMP/default-config"

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
    ('CONFIG_FILE=/etc/config/tvguard','CONFIG_FILE='+tmp+'/etc/config/tvguard'),
    ('DEFAULT_CONFIG=/usr/share/tvguard/default-config','DEFAULT_CONFIG='+tmp+'/default-config'),
    ('CONFIG_OVERLAY_MARK=/etc/.tvguard-config-v1','CONFIG_OVERLAY_MARK='+tmp+'/etc/.tvguard-config-v1'),
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
printf 'legacy-v5\n' > "$TMP/etc/tvguard/calibration-v5.csv"
printf 'legacy-session\n' > "$TMP/etc/tvguard/learning-sessions.csv"

sh "$DST" prepare
[ -f "$TMP/run/tvguard-data/state" ]
[ -f "$TMP/run/tvguard-data/events.log" ]
[ -f "$TMP/run/tvguard-data/calibration-v5.csv" ]
[ -f "$TMP/run/tvguard-data/learning-sessions.csv" ]
[ -f "$TMP/etc/tvguard/state" ]

# Simulate new records created only during the outage.
printf 'volatile-event\n' >> "$TMP/run/tvguard-data/events.log"
printf 'volatile-v5\n' >> "$TMP/run/tvguard-data/calibration-v5.csv"
printf 'volatile-session\n' >> "$TMP/run/tvguard-data/learning-sessions.csv"

# 2) Persistent mount appears: legacy data migrates to mmc, outage-only suffix
# merges once, and the seeded legacy prefix must not be duplicated.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" prepare

[ "$(sh "$DST" root)" = "$TMP/mmc/tvguard" ]
[ -f "$TMP/mmc/tvguard/.layout-v1" ]
grep -qx 'legacy-state' "$TMP/mmc/tvguard/state"
grep -q '^legacy-event
grep -q '^volatile-session$' "$TMP/mmc/tvguard/learning-sessions.csv"
[ "$(grep -c '^legacy-event

# Known legacy files are removed only after verified migration. If the legacy
# directory becomes empty it may become a compatibility symlink.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
    [ ! -e "$TMP/etc/tvguard/events.log" ]
    [ ! -e "$TMP/etc/tvguard/learning-sessions.csv" ]
fi

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^volatile-event
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^legacy-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^volatile-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^legacy-session
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/learning-sessions.csv"
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log")" -eq 1 ]
[ "$(grep -c '^legacy-v5

# Known legacy files are removed only after verified migration. If the legacy
# directory becomes empty it may become a compatibility symlink.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
    [ ! -e "$TMP/etc/tvguard/events.log" ]
    [ ! -e "$TMP/etc/tvguard/learning-sessions.csv" ]
fi

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^volatile-event
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^legacy-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^volatile-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^legacy-session
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/learning-sessions.csv"
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv")" -eq 1 ]
[ "$(grep -c '^legacy-session

# Known legacy files are removed only after verified migration. If the legacy
# directory becomes empty it may become a compatibility symlink.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
    [ ! -e "$TMP/etc/tvguard/events.log" ]
    [ ! -e "$TMP/etc/tvguard/learning-sessions.csv" ]
fi

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^volatile-event
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^legacy-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^volatile-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^legacy-session
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/learning-sessions.csv"
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/learning-sessions.csv")" -eq 1 ]

# Known legacy files are removed only after verified migration. If the legacy
# directory becomes empty it may become a compatibility symlink.
if [ -L "$TMP/etc/tvguard" ]; then
    [ "$(readlink "$TMP/etc/tvguard")" = "$TMP/mmc/tvguard" ]
else
    [ ! -e "$TMP/etc/tvguard/state" ]
    [ ! -e "$TMP/etc/tvguard/events.log" ]
    [ ! -e "$TMP/etc/tvguard/learning-sessions.csv" ]
fi

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^volatile-event
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/events.log"
grep -q '^legacy-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^volatile-v5
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/calibration-v5.csv"
grep -q '^legacy-session
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
 "$TMP/mmc/tvguard/learning-sessions.csv"
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

# 3) UCI config backup: current live custom config becomes the durable copy.
printf 'custom-a\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
cmp "$TMP/etc/config/tvguard" "$TMP/mmc/tvguard/config/tvguard"
[ -f "$TMP/etc/.tvguard-config-v1" ]

# A later admin change updates the durable backup; unchanged config-sync is
# byte-identical and does not need a different file.
printf 'custom-b\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# If the live config disappears on the same overlay, restore it from mmc.
rm -f "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"

# Simulate a freshly rebuilt firmware overlay: marker gone, package default is
# present, durable custom backup exists. The backup must win.
rm -f "$TMP/etc/.tvguard-config-v1"
cp "$TMP/default-config" "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-b' "$TMP/etc/config/tvguard"
grep -qx 'custom-b' "$TMP/mmc/tvguard/config/tvguard"

# Simulate sysupgrade preserving a non-default, newer admin config but not the
# overlay marker. That live custom config must win and refresh the backup.
rm -f "$TMP/etc/.tvguard-config-v1"
printf 'custom-c\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/etc/config/tvguard"
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"

# 4) A later mount outage selects only volatile RAM. Config sync is a no-op
# for persistent backup while mmc is unavailable.
: > "$MOUNTS"
[ "$(sh "$DST" root)" = "$TMP/run/tvguard-data" ]
printf 'custom-d\n' > "$TMP/etc/config/tvguard"
sh "$DST" config-sync
grep -qx 'custom-c' "$TMP/mmc/tvguard/config/tvguard"
case "$(sh "$DST" status)" in
    volatile\|"$TMP/run/tvguard-data"\|persistent_mount_unavailable) : ;;
    *) exit 1 ;;
esac

# When mmc returns on the same overlay, the current live config is backed up.
printf '/dev/mmcblk2p4 %s xfs rw,relatime 0 0\n' "$TMP/mmc" > "$MOUNTS"
sh "$DST" config-sync
grep -qx 'custom-d' "$TMP/mmc/tvguard/config/tvguard"

echo 'PASS: durable data + UCI config survive overlay rebuilds without duplicate learning data'
