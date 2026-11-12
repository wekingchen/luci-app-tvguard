#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/etc/config" "$TMP/etc/tvguard" "$TMP/var/run" "$TMP/persist"
export TVG_TEST_TMP="$TMP"

TODAY="$(date +%Y-%m-%d)"
KEY=0123456789abcdef0123456789abcdef

cat > "$TMP/etc/config/tvguard" <<'EOF'
config tvguard 'main'
        option child_name 'Xiaoming'
        option bark_server 'https://example.invalid'
        option bark_key 'keep-me'
        option enforce '1'
        option allow_enforcement '1'
EOF
cp "$TMP/etc/config/tvguard" "$TMP/original-config"
printf '%s\n' "$KEY" > "$TMP/etc/tvguard/agent-bridge.key"
chmod 600 "$TMP/etc/tvguard/agent-bridge.key"

cat > "$TMP/var/run/tvguard.state" <<EOF
DATA_ROOT_MODE=persistent
TODAY=$TODAY
MODE=child
USED_S=731
WATCH_S=731
WATCH_SCOPE=child
PREV_DATE=none
PREV_WATCH_S=0
EOF
chmod 600 "$TMP/var/run/tvguard.state"

cat > "$TMP/bin/tvguard-data" <<'SH'
#!/bin/sh
set -eu
T="$TVG_TEST_TMP"
case "${1:-root}" in
    root) printf '%s\n' "$T/persist" ;;
    status) printf 'persistent|%s|mounted\n' "$T/persist" ;;
    prepare) mkdir -p "$T/persist" ;;
    backup-config|config-sync|restore-config) : ;;
    *) exit 2 ;;
esac
SH

cat > "$TMP/bin/tvguardctl" <<'SH'
#!/bin/sh
set -eu
T="$TVG_TEST_TMP"
case "${1:-}" in
    sync)
        cp "$T/var/run/tvguard.state" "$T/persist/state"
        chmod 600 "$T/persist/state"
        ;;
    *) : ;;
esac
SH

cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
set -eu
T="$TVG_TEST_TMP"
STATE="$T/uci.state"
[ -f "$STATE" ] || : > "$STATE"
[ "${1:-}" = -q ] && shift
cmd="${1:-}"; shift || :
case "$cmd" in
    get)
        key="$1"
        value="$(sed -n "s|^$key=||p" "$STATE" | tail -n 1)"
        [ -n "$value" ] || exit 1
        printf '%s\n' "$value"
        ;;
    set)
        arg="$1"; key="${arg%%=*}"; value="${arg#*=}"
        value="$(printf '%s' "$value" | sed "s/^'//;s/'$//")"
        grep -v "^$key=" "$STATE" > "$STATE.tmp" || :
        printf '%s=%s\n' "$key" "$value" >> "$STATE.tmp"
        mv "$STATE.tmp" "$STATE"
        ;;
    commit) : ;;
    *) exit 2 ;;
esac
SH

cat > "$TMP/bin/mock-service" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/tvguard-data" "$TMP/bin/tvguardctl" "$TMP/bin/uci" "$TMP/bin/mock-service"
for n in tvguard-retention tvguard-agent-bridge-setup rpcd tvguard tvguard-agent-bridge; do
    cp "$TMP/bin/mock-service" "$TMP/bin/$n"
done
export PATH="$TMP/bin:/usr/bin:/bin"

rewrite_script() {
    src="$1"
    dst="$2"
    python3 - "$src" "$dst" "$TMP" <<'PY'
from pathlib import Path
import sys
src, dst, tmp = sys.argv[1:]
s = Path(src).read_text()
replacements = {
    "/tmp/tvguard-v014-upgrade": tmp + "/upgrade",
    "/tmp/tvguard-config-restore-ned": tmp + "/config-restore-needed",
    "/mnt/mmcblk2p4/tvguard/state": tmp + "/persist/state",
    "/var/run/tvguard.state": tmp + "/var/run/tvguard.state",
    "/etc/config/tvguard": tmp + "/etc/config/tvguard",
    "/etc/tvguard": tmp + "/etc/tvguard",
    "/usr/libexec/tvguard-agent-bridge-setup": tmp + "/bin/tvguard-agent-bridge-setup",
    "/usr/libexec/tvguard-retention": tmp + "/bin/tvguard-retention",
    "/usr/libexec/tvguard-data": tmp + "/bin/tvguard-data",
    "/usr/libexec/tvguardctl": tmp + "/bin/tvguardctl",
    "/etc/init.d/tvguard-agent-bridge": tmp + "/bin/tvguard-agent-bridge",
    "/etc/init.d/rpcd": tmp + "/bin/rpcd",
    "/etc/init.d/tvguard": tmp + "/bin/tvguard",
}
for old in sorted(replacements, key=len, reverse=True):
    s = s.replace(old, replacements[old])
Path(dst).write_text(s)
PY
    chmod +x "$dst"
}

rewrite_script "$ROOT/ipkg/preinst" "$TMP/preinst"
rewrite_script "$ROOT/ipkg/postinst" "$TMP/postinst"

# New preinst runs before opkg removes/replaces the old packages.
sh "$TMP/preinst"
cmp "$TMP/original-config" "$TMP/upgrade/config"
grep -q "^USED_S=731$" "$TMP/upgrade/state"
cmp "$TMP/etc/tvguard/agent-bridge.key" "$TMP/upgrade/agent-bridge.key"

# Simulate relevant damage from the v0.1.13 transition. The integrated
# postinst must restore the original settings, viewing floor and pairing key.
cat > "$TMP/etc/config/tvguard" <<'EOF'
config tvguard 'main'
        option child_name 'Child'
        option bark_key ''
        option enforce '0'
        option allow_enforcement '0'
EOF
cat > "$TMP/persist/state" <<EOF
DATA_ROOT_MODE=persistent
TODAY=$TODAY
MODE=child
USED_S=12
WATCH_S=12
WATCH_SCOPE=child
PREV_DATE=none
PREV_WATCH_S=0
EOF
rm -f "$TMP/var/run/tvguard.state" "$TMP/etc/tvguard/agent-bridge.key"

sh "$TMP/postinst"

cmp "$TMP/original-config" "$TMP/etc/config/tvguard"
grep -q "^USED_S=731$" "$TMP/persist/state"
grep -q "^USED_S=731$" "$TMP/var/run/tvguard.state"
[ "$(cat "$TMP/etc/tvguard/agent-bridge.key")" = "$KEY" ]
[ ! -e "$TMP/upgrade" ]

grep -q "option child_name 'Xiaoming'" "$TMP/etc/config/tvguard"
grep -q "option bark_key 'keep-me'" "$TMP/etc/config/tvguard"
grep -q "option enforce '1'" "$TMP/etc/config/tvguard"
grep -q "option allow_enforcement '1'" "$TMP/etc/config/tvguard"

echo "PASS: integrated v0.1.14 upgrade preserves viewing floor, UCI settings and Agent pairing key"
