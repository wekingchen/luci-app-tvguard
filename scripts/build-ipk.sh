#!/bin/sh
# Build an OpenWrt/opkg-compatible IPK (gzip-compressed GNU tar outer container).
# Do NOT use GNU 'ar': its Debian-format archive has failed on older opkg.
# Development artifact only; not a validated N1 production release.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-0.1.15}"
RELEASE="${2:-4}"
OUT="$ROOT/dist"
PACKAGE="luci-app-tvguard"
ARCH="all"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

mkdir -p "$OUT" "$WORK/data/www" "$WORK/control"
cp -R "$ROOT/root/." "$WORK/data/"
cp -R "$ROOT/htdocs/." "$WORK/data/www/"

# Keep Bridge/Fusion source isolated for tests, but ship it in the main IPK.
# Fail on duplicate file paths instead of overriding core files.
find "$ROOT/bridge/root" -type f | while IFS= read -r source; do
    rel="${source#"$ROOT/bridge/root/"}"
    [ ! -e "$WORK/data/$rel" ] || {
        echo "bridge/core package path collision: $rel" >&2
        exit 1
    }
done
cp -R "$ROOT/bridge/root/." "$WORK/data/"
# Reuse the existing tested BusyBox-safe setup script; never ship the key.
cp "$ROOT/bridge/ipkg/postinst" "$WORK/data/usr/libexec/tvguard-agent-bridge-setup"

for f in \
    etc/init.d/tvguard \
    usr/libexec/tvguardctl \
    usr/libexec/tvguardd \
    usr/libexec/tvguard-status \
    usr/libexec/tvguard-fw \
    usr/libexec/tvguard-firewall-include \
    usr/libexec/tvguard-isolation-audit \
    usr/libexec/tvguard-compat-check \
    usr/libexec/tvguard-shadow \
    usr/libexec/tvguard-learn \
    usr/libexec/tvguard-adaptive \
    usr/libexec/tvguard-retention \
    usr/libexec/tvguard-data \
    usr/libexec/tvguard-soak \
    usr/libexec/tvguard-soak-report \
    usr/libexec/tvguard-daily-report \
    etc/init.d/tvguard-agent-bridge \
    www/cgi-bin/tvguard-agent \
    usr/libexec/tvguard-agent-billing-hint \
    usr/libexec/tvguard-agent-bridge-pair \
    usr/libexec/tvguard-agent-bridge-report \
    usr/libexec/tvguard-agent-bridge-soak \
    usr/libexec/tvguard-agent-fusion \
    usr/libexec/tvguard-agent-bridge-setup; do
    chmod 755 "$WORK/data/$f"
done

# Preserve executable bits and archive files as root:root regardless of CI UID.
# GNU tar is available on the Ubuntu runners used by this repository.
TAR_FLAGS="--format=gnu --numeric-owner --owner=0 --group=0 --sort=name --mtime=@0"
(
    cd "$WORK/data"
    # shellcheck disable=SC2086
    tar $TAR_FLAGS -cf - . | gzip -n > "$WORK/data.tar.gz"
)
INSTALLED_SIZE="$(gzip -cd "$WORK/data.tar.gz" | wc -c | tr -d ' ')"

cat > "$WORK/control/control" <<EOF
Package: $PACKAGE
Version: $VERSION-$RELEASE
Architecture: $ARCH
Maintainer: TV Guard contributors
Section: luci
Priority: optional
Installed-Size: $INSTALLED_SIZE
Depends: luci-base, rpcd, curl, uhttpd
Conflicts: tvguard-agent-bridge
Replaces: tvguard-agent-bridge
Provides: tvguard-agent-bridge
Description: TV Guard LuCI and shadow time-control service for firewall3 / iptables-legacy
EOF

cp "$ROOT/ipkg/preinst" "$ROOT/ipkg/postinst" "$ROOT/ipkg/prerm" "$ROOT/ipkg/conffiles" "$WORK/control/"
chmod 755 "$WORK/control/preinst" "$WORK/control/postinst" "$WORK/control/prerm"

(
    cd "$WORK/control"
    # shellcheck disable=SC2086
    tar $TAR_FLAGS -cf - . | gzip -n > "$WORK/control.tar.gz"
)
printf '2.0\n' > "$WORK/debian-binary"

OUTPUT="$OUT/${PACKAGE}_${VERSION}-${RELEASE}_${ARCH}.ipk"
rm -f "$OUTPUT"
(
    cd "$WORK"
    # OpenWrt's scripts/ipkg-build creates a *gzip-compressed tar* outer IPK.
    # shellcheck disable=SC2086
    tar $TAR_FLAGS -cf - ./debian-binary ./data.tar.gz ./control.tar.gz |
        gzip -n > "$OUTPUT"
)

echo "$OUTPUT"
tar -tzf "$OUTPUT"
