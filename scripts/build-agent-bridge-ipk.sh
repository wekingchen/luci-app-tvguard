#!/bin/sh
# Standalone companion IPK: never repackages an older tvguardctl or firewall.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
OUT="$ROOT/dist"
mkdir -p "$OUT" "$WORK/control"
cp -R "$ROOT/bridge/root" "$WORK/data"
chmod 755 "$WORK/data/www/cgi-bin/tvguard-agent" "$WORK/data/usr/libexec/tvguard-agent-bridge-report"
printf '/etc/tvguard/agent-bridge.key\n' > "$WORK/control/conffiles"
cp "$ROOT/bridge/ipkg/postinst" "$ROOT/bridge/ipkg/prerm" "$WORK/control/"
chmod 755 "$WORK/control/postinst" "$WORK/control/prerm"
INSTALLED="$(du -sk "$WORK/data" | awk '{print $1 * 1024}')"
cat > "$WORK/control/control" <<EOF
Package: tvguard-agent-bridge
Version: 0.2.0-1
Architecture: all
Maintainer: TV Guard contributors
Section: utils
Priority: optional
Installed-Size: $INSTALLED
Depends: uhttpd
Description: TVGuard optional Agent-to-N1 shadow-only ingress companion
EOF
FLAGS="--format=gnu --numeric-owner --owner=0 --group=0 --sort=name --mtime=@0"
(cd "$WORK/data"; tar $FLAGS -cf - . | gzip -n > "$WORK/data.tar.gz")
(cd "$WORK/control"; tar $FLAGS -cf - . | gzip -n > "$WORK/control.tar.gz")
printf '2.0\n' > "$WORK/debian-binary"
PKG="$OUT/tvguard-agent-bridge_0.2.0-1_all.ipk"
(cd "$WORK"; tar $FLAGS -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -n > "$PKG")
test -s "$PKG"
echo "$PKG"
