#!/bin/sh
# Stage a native OpenWrt image without silently overwriting core/Bridge files.
set -eu

src=$1
dst=$2
test -d "$src/root" && test -d "$src/bridge/root" && test -d "$src/native/root"
test -d "$dst/root" || { echo 'TVGuard: missing staging root' >&2; exit 1; }

for subtree in bridge/root native/root; do
    find "$src/$subtree" -type f | while IFS= read -r file; do
        rel=$(printf '%s\n' "$file" | sed "s#^$src/$subtree/##")
        if [ -e "$dst/root/$rel" ] || [ -L "$dst/root/$rel" ]; then
            echo "TVGuard native package path collision: $rel" >&2
            exit 1
        fi
    done
    cp -pR "$src/$subtree/." "$dst/root/"
done

# Never embed generated credentials. Reuse tested runtime setup scripts.
install -d "$dst/root/usr/libexec"
install -m 0755 "$src/bridge/ipkg/postinst" \
    "$dst/root/usr/libexec/tvguard-agent-bridge-setup"
install -m 0755 "$src/ipkg/postinst" \
    "$dst/root/usr/libexec/tvguard-package-postinst"
