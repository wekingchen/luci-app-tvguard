#!/bin/sh
# Build an architecture-independent development IPK without an OpenWrt SDK.
# This is a smoke-test package, not a verified firmware-specific release.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
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
    usr/libexec/tvguard-firewall-include; do
    chmod 755 "$WORK/data/$f"
done

cat > "$WORK/control/control" <<EOF
Package: $PACKAGE
Version: $VERSION-1
Architecture: $ARCH
Maintainer: TV Guard contributors
Section: luci
Priority: optional
Depends: luci-base, rpcd
Description: TV Guard LuCI and shadow time-control service for firewall3 / iptables-legacy
EOF

cp "$ROOT/ipkg/postinst" "$ROOT/ipkg/prerm" "$ROOT/ipkg/conffiles" "$WORK/control/"
chmod 755 "$WORK/control/postinst" "$WORK/control/prerm"

(
    cd "$WORK/data"
    tar -czf "$WORK/data.tar.gz" .
    cd "$WORK/control"
    tar -czf "$WORK/control.tar.gz" .
)
printf '2.0\n' > "$WORK/debian-binary"
OUTPUT="$OUT/${PACKAGE}_${VERSION}-1_${ARCH}.ipk"
(
    cd "$WORK"
    ar rcs "$OUTPUT" debian-binary control.tar.gz data.tar.gz
)
echo "$OUTPUT"
ar t "$OUTPUT"
