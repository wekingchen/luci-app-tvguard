#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

cat > "$TMP/iptables" <<'SH'
#!/bin/sh
[ "$1" = -t ] || exit 2
table="$2"
[ "$3" = -S ] || exit 2
case "${TVG_AUDIT_CASE:-ok}:$table" in
    ok:nat)
        echo '-A PREROUTING -p tcp -j PROXY_NAT'
        ;;
    ok:mangle)
        echo '-A PREROUTING -p tcp -j PROXY_MANGLE'
        ;;
    ok:filter)
        echo '-A FORWARD -j PROXY_FILTER'
        ;;
    ok:raw)
        cat <<'EOF'
-N TVG_RAW
-N TVG_GATE
-A PREROUTING -i br-lan -d 192.168.101.76/32 -m comment --comment TVG_RX_LAN
-A PREROUTING -i br-lan -s 192.168.101.76/32 -j TVG_RAW
-A OUTPUT -o br-lan -d 192.168.101.76/32 -m comment --comment TVG_RX_LOCAL
-A TVG_RAW -m comment --comment TVG_COUNT
-A TVG_RAW -p tcp -m comment --comment TVG_TCP
-A TVG_RAW -p udp -m comment --comment TVG_UDP
-A TVG_RAW -j TVG_GATE
-A TVG_GATE -j RETURN
-A PREROUTING -p tcp -j EXISTING_RAW_PROXY_RULE
EOF
        ;;
    tvg_nat:nat)
        echo '-A PREROUTING -m comment --comment TVG_BAD -j ACCEPT'
        ;;
    tvg_nat:mangle|tvg_nat:filter)
        :
        ;;
    tvg_nat:raw)
        echo '-N TVG_RAW'
        ;;
    passive_target:nat|passive_target:mangle|passive_target:filter)
        :
        ;;
    passive_target:raw)
        cat <<'EOF'
-N TVG_RAW
-N TVG_GATE
-A PREROUTING -i br-lan -s 192.168.101.76/32 -j TVG_RAW
-A PREROUTING -i br-lan -d 192.168.101.76/32 -m comment --comment TVG_RX_LAN -j RETURN
-A TVG_RAW -m comment --comment TVG_COUNT
-A TVG_RAW -p tcp -m comment --comment TVG_TCP
-A TVG_RAW -p udp -m comment --comment TVG_UDP
-A TVG_RAW -j TVG_GATE
-A TVG_GATE -j RETURN
EOF
        ;;
    unexpected_chain:nat|unexpected_chain:mangle|unexpected_chain:filter)
        :
        ;;
    unexpected_chain:raw)
        cat <<'EOF'
-N TVG_RAW
-N TVG_GATE
-N TVG_FOREIGN
-A TVG_GATE -j RETURN
EOF
        ;;
    extra_gate:nat|extra_gate:mangle|extra_gate:filter)
        :
        ;;
    extra_gate:raw)
        cat <<'EOF'
-N TVG_RAW
-N TVG_GATE
-A TVG_GATE -j RETURN
-A TVG_GATE -j DROP
EOF
        ;;
    *)
        exit 2
        ;;
esac
SH
chmod +x "$TMP/iptables"

AUDIT="$TMP/audit"
python3 - "$ROOT/root/usr/libexec/tvguard-isolation-audit" "$AUDIT" "$TMP/iptables" <<'PY'
from pathlib import Path
import sys
src,dest,ipt=sys.argv[1:]
s=Path(src).read_text()
anchor='IPT=/usr/sbin/iptables'
assert anchor in s
Path(dest).write_text(s.replace(anchor,'IPT='+ipt,1))
PY
chmod +x "$AUDIT"

export TVG_AUDIT_CASE=ok
[ "$(sh "$AUDIT")" = ok ]

for bad in tvg_nat passive_target unexpected_chain extra_gate; do
    export TVG_AUDIT_CASE="$bad"
    if sh "$AUDIT" >"$TMP/out" 2>"$TMP/err"; then
        echo "FAIL: audit accepted unsafe case $bad" >&2
        exit 1
    fi
    grep -q '^unsafe:' "$TMP/out"
done

echo "PASS: runtime audit allows unrelated proxy rules and rejects TVG namespace/table/target violations"
