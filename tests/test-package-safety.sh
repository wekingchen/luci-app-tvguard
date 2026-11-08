#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin"
STATE="$TMP/uci.state"
LOG="$TMP/actions.log"
: > "$STATE"
: > "$LOG"

cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
set -eu
UCI_STATE="$TVG_UCI_STATE"
UCI_LOG="$TVG_ACTION_LOG"
[ "${1:-}" = -q ] && shift
UCI_CMD="${1:-}"
shift || :

get_value() {
    UCI_LOOKUP="$1"
    sed -n "s|^$UCI_LOOKUP=||p" "$UCI_STATE" | tail -n 1
}

case "$UCI_CMD" in
    get)
        UCI_VALUE="$(get_value "${1:-}")"
        [ -n "$UCI_VALUE" ] || exit 1
        printf '%s\n' "$UCI_VALUE"
        ;;
    set)
        UCI_ARG="${1:-}"
        UCI_KEY="${UCI_ARG%%=*}"
        UCI_VALUE="${UCI_ARG#*=}"
        UCI_VALUE="$(printf '%s' "$UCI_VALUE" | sed "s/^'//;s/'$//")"
        grep -v "^$UCI_KEY=" "$UCI_STATE" > "$UCI_STATE.tmp" || :
        printf '%s=%s\n' "$UCI_KEY" "$UCI_VALUE" >> "$UCI_STATE.tmp"
        mv "$UCI_STATE.tmp" "$UCI_STATE"
        printf 'set %s=%s\n' "$UCI_KEY" "$UCI_VALUE" >> "$UCI_LOG"
        ;;
    delete)
        UCI_KEY="${1:-}"
        grep -v "^$UCI_KEY=" "$UCI_STATE" > "$UCI_STATE.tmp" || :
        mv "$UCI_STATE.tmp" "$UCI_STATE"
        printf 'delete %s\n' "$UCI_KEY" >> "$UCI_LOG"
        ;;
    commit)
        printf 'commit %s\n' "${1:-}" >> "$UCI_LOG"
        ;;
    *)
        echo "unexpected uci: $UCI_CMD $*" >&2
        exit 2
        ;;
esac
SH

cat > "$TMP/mock-action" <<'SH'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TVG_ACTION_LOG"
exit 0
SH
chmod +x "$TMP/bin/uci" "$TMP/mock-action"
for name in rpcd tvguard tvguardctl; do
    cp "$TMP/mock-action" "$TMP/$name"
done

cat > "$TMP/tvguard-fw" <<'SH'
#!/bin/sh
printf 'tvguard-fw %s\n' "$*" >> "$TVG_ACTION_LOG"
if [ "${1:-}" = remove ]; then
    exit "${TVG_FW_REMOVE_EXIT:-0}"
fi
exit 0
SH
chmod +x "$TMP/"*

export PATH="$TMP/bin:/usr/bin:/bin"
export TVG_UCI_STATE="$STATE"
export TVG_ACTION_LOG="$LOG"
export TVG_FW_REMOVE_EXIT=0

rewrite() {
    src="$1"
    dest="$2"
    python3 - "$src" "$dest" "$TMP" <<'PY'
from pathlib import Path
import sys
src, dst, tmp = sys.argv[1:]
text = Path(src).read_text()
text = text.replace("/etc/init.d/rpcd", tmp + "/rpcd")
text = text.replace("/etc/init.d/tvguard", tmp + "/tvguard")
text = text.replace("/usr/libexec/tvguardctl", tmp + "/tvguardctl")
text = text.replace("/usr/libexec/tvguard-fw", tmp + "/tvguard-fw")
Path(dst).write_text(text)
PY
    chmod +x "$dest"
}
rewrite "$ROOT/ipkg/postinst" "$TMP/postinst"
rewrite "$ROOT/ipkg/prerm" "$TMP/prerm"

write_proxy_section() {
    cat >> "$STATE" <<'EOF'
firewall.proxy=include
firewall.proxy.type=script
firewall.proxy.path=/usr/share/proxy/firewall.include
firewall.proxy.enabled=1
EOF
}
assert_proxy_section() {
    grep -q '^firewall.proxy=include$' "$STATE"
    grep -q '^firewall.proxy.type=script$' "$STATE"
    grep -q '^firewall.proxy.path=/usr/share/proxy/firewall.include$' "$STATE"
    grep -q '^firewall.proxy.enabled=1$' "$STATE"
}
reset() {
    : > "$STATE"
    : > "$LOG"
    write_proxy_section
}
owned() {
    : > "$STATE"
    write_proxy_section
    cat >> "$STATE" <<'EOF'
firewall.tvguard=include
firewall.tvguard.type=script
firewall.tvguard.path=/usr/libexec/tvguard-firewall-include
firewall.tvguard.enabled=1
firewall.tvguard.reload=1
EOF
}
foreign() {
    : > "$STATE"
    write_proxy_section
    cat >> "$STATE" <<'EOF'
firewall.tvguard=include
firewall.tvguard.type=script
firewall.tvguard.path=/usr/libexec/not-tvguard
firewall.tvguard.enabled=1
EOF
}

# Clean install adds only TV Guard ownership metadata and preserves proxy config.
reset
cp "$STATE" "$TMP/proxy.before"
sh "$TMP/postinst"
assert_proxy_section
grep -q '^firewall.tvguard=include$' "$STATE"
grep -q '^firewall.tvguard.type=script$' "$STATE"
grep -q '^firewall.tvguard.path=/usr/libexec/tvguard-firewall-include$' "$STATE"
grep -q '^commit firewall$' "$LOG"
grep -q '^tvguard enable$' "$LOG"
grep -q '^tvguard start$' "$LOG"
! grep -q 'firewall restart\|firewall reload' "$LOG"

# Existing owned section is accepted but not rewritten/committed.
owned
: > "$LOG"
sh "$TMP/postinst"
assert_proxy_section
! grep -q '^set firewall\.' "$LOG"
! grep -q '^commit firewall$' "$LOG"
grep -q '^tvguard start$' "$LOG"

# Foreign same-name section is a hard stop: no mutation and no service start.
foreign
cp "$STATE" "$TMP/foreign.before"
: > "$LOG"
if sh "$TMP/postinst" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: postinst accepted foreign firewall.tvguard" >&2
    exit 1
fi
cmp "$STATE" "$TMP/foreign.before"
assert_proxy_section
! grep -q '^set firewall\.' "$LOG"
! grep -q '^delete firewall\.' "$LOG"
! grep -q '^tvguard start$' "$LOG"

# Uninstall never deletes a foreign section.
foreign
cp "$STATE" "$TMP/foreign.before"
: > "$LOG"
sh "$TMP/prerm"
cmp "$STATE" "$TMP/foreign.before"
assert_proxy_section
! grep -q '^delete firewall\.tvguard$' "$LOG"
grep -q '^tvguard stop$' "$LOG"
grep -q '^tvguard-fw remove$' "$LOG"

# Failed firewall detach aborts uninstall and retains all ownership metadata.
owned
cp "$STATE" "$TMP/owned.before"
: > "$LOG"
export TVG_FW_REMOVE_EXIT=9
if sh "$TMP/prerm" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: prerm ignored TV firewall detach failure" >&2
    exit 1
fi
cmp "$STATE" "$TMP/owned.before"
assert_proxy_section
grep -q '^firewall.tvguard=include$' "$STATE"
! grep -q '^delete firewall\.tvguard$' "$LOG"
grep -q 'aborting uninstall' "$TMP/err"
grep -q '^tvguardctl enforce off

# Owned section is deleted only after firewall detach succeeds; proxy survives.
owned
: > "$LOG"
sh "$TMP/prerm"
assert_proxy_section
! grep -q '^firewall.tvguard=' "$STATE"
grep -q '^delete firewall.tvguard$' "$LOG"
grep -q '^commit firewall$' "$LOG"

echo "PASS: package ownership is isolated, proxy UCI survives, and failed detach aborts uninstall"
 "$LOG"
grep -q '^tvguard stop

# Owned section is deleted only after firewall detach succeeds; proxy survives.
owned
: > "$LOG"
sh "$TMP/prerm"
assert_proxy_section
! grep -q '^firewall.tvguard=' "$STATE"
grep -q '^delete firewall.tvguard$' "$LOG"
grep -q '^commit firewall$' "$LOG"

echo "PASS: package ownership is isolated, proxy UCI survives, and failed detach aborts uninstall"
 "$LOG"
grep -q '^tvguard start

# Owned section is deleted only after firewall detach succeeds; proxy survives.
owned
: > "$LOG"
sh "$TMP/prerm"
assert_proxy_section
! grep -q '^firewall.tvguard=' "$STATE"
grep -q '^delete firewall.tvguard$' "$LOG"
grep -q '^commit firewall$' "$LOG"

echo "PASS: package ownership is isolated, proxy UCI survives, and failed detach aborts uninstall"
 "$LOG"
export TVG_FW_REMOVE_EXIT=0

# Owned section is deleted only after firewall detach succeeds; proxy survives.
owned
: > "$LOG"
sh "$TMP/prerm"
assert_proxy_section
! grep -q '^firewall.tvguard=' "$STATE"
grep -q '^delete firewall.tvguard$' "$LOG"
grep -q '^commit firewall$' "$LOG"

echo "PASS: package ownership is isolated, proxy UCI survives, and failed detach aborts uninstall"
