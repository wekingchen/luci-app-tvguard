#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/tables"

cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
[ "$1" = -q ] && shift
[ "$1" = get ] || exit 2
case "$2" in
    tvguard.main.enforce) echo "${TVG_COMPAT_ENFORCE:-0}" ;;
    tvguard.main.allow_enforcement) echo "${TVG_COMPAT_ARMED:-0}" ;;
    tvguard.main.observe_reply) echo "${TVG_COMPAT_OBSERVE:-0}" ;;
    firewall.tvguard) echo "${TVG_COMPAT_INCLUDE_TYPE:-include}" ;;
    firewall.tvguard.type) echo "${TVG_COMPAT_INCLUDE_MODE:-script}" ;;
    firewall.tvguard.path) echo "${TVG_COMPAT_INCLUDE_PATH:-/usr/libexec/tvguard-firewall-include}" ;;
    *) exit 1 ;;
esac
SH

cat > "$TMP/iptables" <<'SH'
#!/bin/sh
if [ "$1" = --version ]; then
    echo 'iptables v1.8.7 (legacy)'
    exit 0
fi
if [ "$1" = -w ] && [ "$2" = 2 ]; then shift 2; fi
[ "$1" = -t ] || exit 2
table="$2"
[ "$3" = -S ] || exit 2
[ "${TVG_COMPAT_FAIL_TABLE:-none}" != "$table" ] || exit 4
cat "$TVG_COMPAT_TABLE_DIR/$table"
SH

cat > "$TMP/audit" <<'SH'
#!/bin/sh
printf '%s\n' "${TVG_COMPAT_AUDIT:-ok}"
[ "${TVG_COMPAT_AUDIT:-ok}" = ok ]
SH

cat > "$TMP/fw" <<'SH'
#!/bin/sh
[ "$1" = inspect ] || exit 2
printf '%s\n' "${TVG_COMPAT_GATE:-allowed}"
SH

cat > "$TMP/ctl" <<'SH'
#!/bin/sh
[ "$1" = sync ] || exit 2
case "${TVG_COMPAT_MUTATE:-tvg_only}" in
    fail) exit 7 ;;
    tvg_only)
        printf '%s\n' '-N TVG_TEST_ONLY' >> "$TVG_COMPAT_TABLE_DIR/raw"
        ;;
    foreign)
        printf '%s\n' '-A PREROUTING -j PROXY_CHANGED_BY_BUG' >> "$TVG_COMPAT_TABLE_DIR/raw"
        ;;
    none) : ;;
esac
SH
chmod +x "$TMP/bin/uci" "$TMP/iptables" "$TMP/audit" "$TMP/fw" "$TMP/ctl"

for table in raw mangle nat filter; do
    : > "$TMP/tables/$table"
done
cat > "$TMP/tables/raw" <<'EOF'
-A PREROUTING -p tcp -j EXISTING_PROXY_RAW
-N TVG_RAW
-A PREROUTING -i br-lan -s 192.168.101.76/32 -j TVG_RAW
EOF
cat > "$TMP/tables/mangle" <<'EOF'
-A PREROUTING -p tcp -j EXISTING_PROXY_MANGLE
EOF
cat > "$TMP/tables/nat" <<'EOF'
-A PREROUTING -p tcp -j EXISTING_PROXY_NAT
EOF
cat > "$TMP/tables/filter" <<'EOF'
-A FORWARD -j EXISTING_FILTER
EOF

CHECK="$TMP/check"
python3 - "$ROOT/root/usr/libexec/tvguard-compat-check" "$CHECK" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
s=Path(src).read_text()
mapping={
    'IPT=/usr/sbin/iptables':'IPT='+tmp+'/iptables',
    'CTL=/usr/libexec/tvguardctl':'CTL='+tmp+'/ctl',
    'FW=/usr/libexec/tvguard-fw':'FW='+tmp+'/fw',
    'AUDIT=/usr/libexec/tvguard-isolation-audit':'AUDIT='+tmp+'/audit',
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin':'PATH='+tmp+'/bin:/usr/bin:/bin',
}
for a,b in mapping.items():
    assert a in s,a
    s=s.replace(a,b,1)
Path(dst).write_text(s)
PY
chmod +x "$CHECK"

export TVG_COMPAT_TABLE_DIR="$TMP/tables"
export TVG_COMPAT_ENFORCE=0
export TVG_COMPAT_ARMED=0
export TVG_COMPAT_OBSERVE=0
export TVG_COMPAT_AUDIT=ok
export TVG_COMPAT_GATE=allowed
export TVG_COMPAT_FAIL_TABLE=none
export TVG_COMPAT_INCLUDE_TYPE=include
export TVG_COMPAT_INCLUDE_MODE=script
export TVG_COMPAT_INCLUDE_PATH=/usr/libexec/tvguard-firewall-include

# TVG-only changes are filtered from snapshots, so proxy rules remain identical.
export TVG_COMPAT_MUTATE=tvg_only
sh "$CHECK" > "$TMP/pass"
grep -q '^result=PASS$' "$TMP/pass"
grep -q '^proxy_rules_unchanged=1$' "$TMP/pass"
grep -q '^isolation_audit=ok$' "$TMP/pass"
grep -q 'iptables v1.8.7 (legacy)' "$TMP/pass"

# Reset raw table and simulate an accidental non-TVG rule change.
cat > "$TMP/tables/raw" <<'EOF'
-A PREROUTING -p tcp -j EXISTING_PROXY_RAW
-N TVG_RAW
-A PREROUTING -i br-lan -s 192.168.101.76/32 -j TVG_RAW
EOF
export TVG_COMPAT_MUTATE=foreign
if sh "$CHECK" > "$TMP/fail" 2>&1; then
    echo "FAIL: compatibility check accepted a changed proxy rule set" >&2
    exit 1
fi
grep -q '^reason=non_tvg_rules_changed$' "$TMP/fail"

# Unsafe operating switches must fail before the TVG sync path runs.
cat > "$TMP/tables/raw" <<'EOF'
-A PREROUTING -p tcp -j EXISTING_PROXY_RAW
-N TVG_RAW
-A PREROUTING -i br-lan -s 192.168.101.76/32 -j TVG_RAW
EOF
export TVG_COMPAT_MUTATE=none
export TVG_COMPAT_ENFORCE=1
if sh "$CHECK" > "$TMP/fail-mode" 2>&1; then
    echo "FAIL: compatibility check ran while enforcement was enabled" >&2
    exit 1
fi
grep -q '^reason=enforce_must_be_0$' "$TMP/fail-mode"
export TVG_COMPAT_ENFORCE=0

export TVG_COMPAT_ARMED=1
if sh "$CHECK" > "$TMP/fail-armed" 2>&1; then exit 1; fi
grep -q '^reason=allow_enforcement_must_be_0$' "$TMP/fail-armed"
export TVG_COMPAT_ARMED=0

export TVG_COMPAT_OBSERVE=1
if sh "$CHECK" > "$TMP/fail-observe" 2>&1; then exit 1; fi
grep -q '^reason=observe_reply_must_be_0$' "$TMP/fail-observe"
export TVG_COMPAT_OBSERVE=0

export TVG_COMPAT_AUDIT='unsafe:test'
if sh "$CHECK" > "$TMP/fail-audit" 2>&1; then exit 1; fi
grep -q '^reason=isolation_before_unsafe:test$' "$TMP/fail-audit"
export TVG_COMPAT_AUDIT=ok

export TVG_COMPAT_GATE=blocked
if sh "$CHECK" > "$TMP/fail-gate" 2>&1; then exit 1; fi
grep -q '^reason=gate_before_blocked$' "$TMP/fail-gate"
export TVG_COMPAT_GATE=allowed

export TVG_COMPAT_FAIL_TABLE=mangle
if sh "$CHECK" > "$TMP/fail-table" 2>&1; then exit 1; fi
grep -q '^reason=snapshot_before_unavailable$' "$TMP/fail-table"
export TVG_COMPAT_FAIL_TABLE=none

export TVG_COMPAT_MUTATE=fail
if sh "$CHECK" > "$TMP/fail-sync" 2>&1; then exit 1; fi
grep -q '^reason=tvguard_sync_failed$' "$TMP/fail-sync"
export TVG_COMPAT_MUTATE=none

export TVG_COMPAT_INCLUDE_PATH=/usr/libexec/foreign-firewall-include
if sh "$CHECK" > "$TMP/fail-include" 2>&1; then exit 1; fi
grep -q '^reason=firewall_include_path_unexpected$' "$TMP/fail-include"
export TVG_COMPAT_INCLUDE_PATH=/usr/libexec/tvguard-firewall-include

echo "PASS: compatibility checker validates safe switches, audit/gate, snapshots, sync and firewall include ownership"
