#!/bin/sh
# 在 PATH 不含 od/hexdump/xxd 时，验证配对码与会话令牌的强随机生成。
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/bin"
for tool in dd mktemp wc tr sha256sum cut rm; do
    target="$(command -v "$tool")"
    [ -n "$target" ] && [ -x "$target" ] || exit 1
    ln -s "$target" "$WORK/bin/$tool"
done
[ ! -e "$WORK/bin/od" ] && [ ! -e "$WORK/bin/hexdump" ] && [ ! -e "$WORK/bin/xxd" ]
for size in 16 32; do
    first="$(PATH="$WORK/bin" /bin/sh "$ROOT/root/usr/libexec/tvguard-random-hex" "$size")"
    second="$(PATH="$WORK/bin" /bin/sh "$ROOT/root/usr/libexec/tvguard-random-hex" "$size")"
    [ "$(printf '%s' "$first" | wc -c)" -eq "$((size * 2))" ]
    [ "$(printf '%s' "$second" | wc -c)" -eq "$((size * 2))" ]
    case "$first$second" in *[!0-9a-f]*) echo 'invalid hex' >&2; exit 1 ;; esac
    [ "$first" != "$second" ] || { echo 'random collision' >&2; exit 1; }
done
if PATH="$WORK/bin" /bin/sh "$ROOT/root/usr/libexec/tvguard-random-hex" 0 >/dev/null 2>&1; then
    echo 'invalid random size accepted' >&2
    exit 1
fi
echo 'PASS: random 128/256-bit tokens on OpenWrt-like PATH without od/hexdump/xxd'
