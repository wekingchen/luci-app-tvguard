#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/etc/config" "$TMP/bin"
LOG="$TMP/data.log"
: > "$LOG"

cat > "$TMP/data" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$TVG_PREINST_LOG"
exit 0
SH
chmod +x "$TMP/data"
export TVG_PREINST_LOG="$LOG"

SRC="$ROOT/ipkg/preinst"
DST="$TMP/preinst"
python3 - "$SRC" "$DST" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
s=Path(src).read_text()
s=s.replace('/etc/config/tvguard', tmp+'/etc/config/tvguard')
s=s.replace('/usr/libexec/tvguard-data', tmp+'/data')
s=s.replace('/tmp/tvguard-config-restore-needed', tmp+'/restore-needed')
s=s.replace('/tmp/tvguard-v014-upgrade', tmp+'/upgrade')
Path(dst).write_text(s)
PY
chmod +x "$DST"

# Existing config: after the legacy v0.1.13 prerm, the integrated preinst
# snapshots the current UCI file into a private migration directory and does
# not request fresh-overlay restoration.
printf 'custom\n' > "$TMP/etc/config/tvguard"
: > "$LOG"
sh "$DST"
cmp "$TMP/etc/config/tvguard" "$TMP/upgrade/config"
[ -f "$TMP/upgrade/pending" ]
[ ! -e "$TMP/restore-needed" ]

# Fresh overlay: no config existed before package extraction, so postinst must
# be told to restore the durable mmc copy after default files are unpacked.
rm -rf "$TMP/upgrade"
rm -f "$TMP/etc/config/tvguard"
: > "$LOG"
sh "$DST"
[ -f "$TMP/restore-needed" ]
[ ! -e "$TMP/upgrade" ]
[ ! -s "$LOG" ]

echo 'PASS: preinst snapshots integrated upgrades and distinguishes fresh overlay'
