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
state="$TVG_UCI_STATE"
log="$TVG_ACTION_LOG"
quiet=0
if [ "${1:-}" = -q ]; then quiet=1; shift; fi
cmd="${1:-}"; shift || :
getv() {
    key="$1"
    sed -n "s|^$key=||p" "$state" | tail -n 1
}
case "$cmd" in
    get)
        v="$(getv "${1:-}")"
        [ -n "$v" ] || exit 1
        printf '%s\n' "$v"
        ;;
    set)
        arg="${1:-}"
        key="${arg%%=*}"
        val="${arg#*=}"
        val="$(printf '%s' "$val" | sed "s/^'//;s/'$//")"
        grep -v "^$key=" "$state" > "$state.tmp" || :
        printf '%s=%s\n' "$key" "$val" >> "$state.tmp"
        mv "$state.tmp" "$state"
        printf 'set %s=%s\n' "$key" "$val" >> "$log"
        ;;
    delete)
        key="${1:-}"
        grep -v "^$key=" "$state" > "$state.tmp" || :
        mv "$state.tmp" "$state"
        printf 'delete %s\n' "$key" >> "$log"
        ;;
    commit)
        printf 'commit %s\n' "${1:-}" >> "$log"
        ;;
    *)
        echo "unexpected uci: $cmd $*" >&2
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
for name in rpcd tvguard; do
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
    src="$1"; dest="$2"
    python3 - "$src" "$dest" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
s=Path(src).read_text()
s=s.replace("/etc/init.d/rpcd", tmp+"/rpcd")
s=s.replace("/etc/init.d/tvguard", tmp+"/tvguard")
s=s.replace("/usr/libexec/tvguard-fw", tmp+"/tvguard-fw")
Path(dst).write_text(s)
PY
    chmod +x "$dest"
}
rewrite "$ROOT/ipkg/postinst" "$TMP/postinst"
rewrite "$ROOT/ipkg/prerm" "$TMP/prerm"

reset() {
    : > "$STATE"
    : > "$LOG"
}
owned() {
    cat > "$STATE" <<'EOF'
firewall.tvguard=include
firewall.tvguard.type=script
firewall.tvguard.path=/usr/libexec/tvguard-firewall-include
firewall.tvguard.enabled=1
firewall.tvguard.reload=1
EOF
}
foreign() {
    cat > "$STATE" <<'EOF'
firewall.tvguard=include
firewall.tvguard.type=script
firewall.tvguard.path=/usr/libexec/not-tvguard
firewall.tvguard.enabled=1
EOF
}

# Clean install claims only the TV Guard section and starts only its own service.
reset
sh "$TMP/postinst"
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
! grep -q '^set firewall\.' "$LOG"
! grep -q '^delete firewall\.' "$LOG"
! grep -q '^tvguard start$' "$LOG"

# Uninstall never deletes a foreign section, though it may clean TVG runtime chains.
foreign
cp "$STATE" "$TMP/foreign.before"
: > "$LOG"
sh "$TMP/prerm"
cmp "$STATE" "$TMP/foreign.before"
! grep -q '^delete firewall\.tvguard$' "$LOG"
grep -q '^tvguard stop$' "$LOG"
grep -q '^tvguard-fw remove$' "$LOG"

# Failed firewall detach aborts uninstall and retains the owned UCI include.
owned
: > "$LOG"
export TVG_FW_REMOVE_EXIT=9
if sh "$TMP/prerm" >"$TMP/out" 2>"$TMP/err"; then
    echo "FAIL: prerm ignored TV firewall detach failure" >&2
    exit 1
fi
grep -q '^firewall.tvguard=include
 "$STATE"
! grep -q '^delete firewall.tvguard
 "$LOG"
grep -q 'aborting uninstall' "$TMP/err"
export TVG_FW_REMOVE_EXIT=0

# Owned section is deleted only after firewall detach succeeds.
owned
: > "$LOG"
sh "$TMP/prerm"
! grep -q '^firewall.tvguard=' "$STATE"
grep -q '^delete firewall.tvguard
 "$LOG"
grep -q '^commit firewall
 "$LOG"

echo "PASS: package ownership is isolated and failed firewall detach cannot leave a dangling hook after uninstall"
