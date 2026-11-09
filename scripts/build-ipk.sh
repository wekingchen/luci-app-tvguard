#!/bin/sh
# Build an OpenWrt/opkg-compatible IPK (gzip-compressed GNU tar outer container).
# Do NOT use GNU 'ar': its Debian-format archive has failed on older opkg.
# Development artifact only; not a validated N1 production release.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-0.1.13}"
OUT="$ROOT/dist"
PACKAGE="luci-app-tvguard"
ARCH="all"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

mkdir -p "$OUT" "$WORK/data/www" "$WORK/control"
cp -R "$ROOT/root/." "$WORK/data/"
cp -R "$ROOT/htdocs/." "$WORK/data/www/"

for f in \
    etc/init.d/tvguard \
    usr/libexec/tvguardctl \
    usr/libexec/tvguardd \
    usr/libexec/tvguard-status \
    usr/libexec/tvguard-fw \
    usr/libexec/tvguard-firewall-include \
    usr/libexec/tvguard-isolation-audit \
    usr/libexec/tvguard-compat-check \
    usr/libexec/tvguard-shadow; do
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
Version: $VERSION-1
Architecture: $ARCH
Maintainer: TV Guard contributors
Section: luci
Priority: optional
Installed-Size: $INSTALLED_SIZE
Depends: luci-base, rpcd
Description: TV Guard LuCI and shadow time-control service for firewall3 / iptables-legacy
EOF

cp "$ROOT/ipkg/postinst" "$ROOT/ipkg/prerm" "$ROOT/ipkg/conffiles" "$WORK/control/"
chmod 755 "$WORK/control/postinst" "$WORK/control/prerm"

(
    cd "$WORK/control"
    # shellcheck disable=SC2086
    tar $TAR_FLAGS -cf - . | gzip -n > "$WORK/control.tar.gz"
)
printf '2.0\n' > "$WORK/debian-binary"

OUTPUT="$OUT/${PACKAGE}_${VERSION}-1_${ARCH}.ipk"
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
