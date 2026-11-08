#!/bin/sh
# Mock the firewall3 legacy API; never creates real iptables rules.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin"

cat > "$TMP/bin/uci" <<'EOS'
#!/bin/sh
[ "${1:-}" = -q ] && shift
[ "${1:-}" = get ] || exit 2
case "${2:-}" in
    tvguard.main.ip) echo 192.168.101.76 ;;
    tvguard.main.interface) echo br-lan ;;
    tvguard.main.enforce) echo "${MOCK_ENFORCE:-0}" ;;
    tvguard.main.allow_enforcement) echo "${MOCK_ARMED:-0}" ;;
    tvguard.main.observe_reply) echo "${MOCK_OBSERVE_REPLY:-0}" ;;
    *) exit 1 ;;
esac
EOS
cat > "$TMP/iptables" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys
p=pathlib.Path(os.environ["MOCK_IPT_STATE"])
s=json.loads(p.read_text())
argv=sys.argv[1:]
if argv[:2]==["-w","2"]:
    argv=argv[2:]
assert argv[:2]==["-t","raw"], argv
argv=argv[2:]
op,chain,*args=argv
rules=s["chains"]
def commit():
    p.write_text(json.dumps(s))
if op == "-N":
    if chain in rules: sys.exit(1)
    rules[chain]=[]
elif op == "-C":
    if args not in rules.get(chain,[]): sys.exit(1)
elif op in ("-A","-I"):
    if chain not in rules: sys.exit(1)
    if op=="-I" and args and args[0].isdigit():
        index=int(args.pop(0))-1
    else: index=0
    if op=="-A": rules[chain].append(args)
    else: rules[chain].insert(index,args)
elif op=="-R":
    idx=int(args.pop(0))-1
    if chain not in rules or idx>=len(rules[chain]): sys.exit(1)
    rules[chain][idx]=args
elif op=="-D":
    if chain not in rules or args not in rules[chain]: sys.exit(1)
    rules[chain].remove(args)
elif op=="-F":
    if chain not in rules: sys.exit(1)
    rules[chain]=[]
elif op=="-X":
    if chain not in rules: sys.exit(1)
    for key,entries in rules.items():
        if any(len(r)>1 and r[-2:]==["-j",chain] for r in entries): sys.exit(1)
    if rules[chain]: sys.exit(1)
    del rules[chain]
elif op=="-L":
    if chain not in rules: sys.exit(1)
    print(f"Chain {chain} (1 references)")
    print(" pkts bytes target prot opt in out source destination")
    count={"TVG_COUNT":(200,4096),"TVG_TCP":(120,1024),"TVG_UDP":(70,3000),
           "TVG_RX_LAN":(75,45000),"TVG_RX_LOCAL":(30,12000)}
    for r in rules[chain]:
        label=next((r[i+1] for i,a in enumerate(r[:-1]) if a=="--comment"),"OTHER")
        pp,bb=count.get(label,(0,0))
        print(f" {pp} {bb} all -- * * 0.0.0.0/0 0.0.0.0/0 /* {label} */")
else:
    raise SystemExit("unknown mock action: "+repr(argv))
commit()
PY
cat > "$TMP/audit" <<'SH'
#!/bin/sh
case "${MOCK_ISOLATION:-ok}" in
    ok) echo ok; exit 0 ;;
    *) echo "unsafe:test"; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/uci" "$TMP/iptables" "$TMP/audit"

python3 - "$TMP/state.json" <<'PY'
import json,sys
p=sys.argv[1]
# A non-TVG rule that must survive the full lifecycle.
json.dump({"chains":{
    "PREROUTING":[
        ["-s","203.0.113.5","-j","PROXY_RAW_A"],
        ["-d","198.51.100.8","-j","PROXY_RAW_B"]
    ],
    "OUTPUT":[
        ["-d","203.0.113.6","-j","PROXY_OUT_A"],
        ["-s","198.51.100.9","-j","PROXY_OUT_B"]
    ],
    "PROXY_RAW_A":[["-m","comment","--comment","existing_proxy_rule_a"]],
    "PROXY_RAW_B":[["-m","comment","--comment","existing_proxy_rule_b"]],
    "PROXY_OUT_A":[["-m","comment","--comment","existing_proxy_out_a"]],
    "PROXY_OUT_B":[["-m","comment","--comment","existing_proxy_out_b"]]
}},open(p,"w"))
PY
export MOCK_IPT_STATE="$TMP/state.json"
export MOCK_ENFORCE=0
export MOCK_ARMED=0
export MOCK_OBSERVE_REPLY=0
export MOCK_ISOLATION=ok

# A disposable test copy has a mock IPT and PATH; installed binary is fixed.
FW="$TMP/tvguard-fw"
python3 - "$ROOT/root/usr/libexec/tvguard-fw" "$FW" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dest,root=sys.argv[1:]
s=Path(src).read_text()
s=s.replace("IPT=/usr/sbin/iptables","IPT="+root+"/iptables",1)
s=s.replace("AUDIT=/usr/libexec/tvguard-isolation-audit","AUDIT="+root+"/audit",1)
Path(dest).write_text(s)
PY
PATH="$TMP/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
sh "$FW" sync
[ "$(sh "$FW" inspect)" = allowed ]
[ "$(sh "$FW" sample)" = '200 4096 120 1024 70 3000' ]
[ "$(sh "$FW" inspect-reply)" = disabled ]
if sh "$FW" sample-reply >/dev/null 2>&1; then
    echo "ERROR: reply sampled while disabled" >&2
    exit 1
fi
sh "$FW" sync
python3 - "$TMP/state.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))["chains"]
assert len(c["PREROUTING"])==3, c["PREROUTING"]
# Existing proxy-like rules keep their relative order and exact arguments.
assert c["PREROUTING"][-2:]==[
    ["-s","203.0.113.5","-j","PROXY_RAW_A"],
    ["-d","198.51.100.8","-j","PROXY_RAW_B"],
],c["PREROUTING"]
assert c["OUTPUT"]==[
    ["-d","203.0.113.6","-j","PROXY_OUT_A"],
    ["-s","198.51.100.9","-j","PROXY_OUT_B"],
],c["OUTPUT"]
assert sum(1 for x in c["TVG_RAW"] if "TVG_COUNT" in x)==1
assert sum(1 for x in c["TVG_RAW"] if "TVG_TCP" in x)==1
assert sum(1 for x in c["TVG_RAW"] if "TVG_UDP" in x)==1
PY
# Gate changes are deliberately decoupled from the optional observer.
# Even with the option set, direct mode/quota changes must not create observer rules.
export MOCK_OBSERVE_REPLY=1
sh "$FW" gate 1
[ "$(sh "$FW" inspect)" = blocked ]
[ "$(sh "$FW" inspect-reply)" = unavailable ]
sh "$FW" gate 0
[ "$(sh "$FW" inspect)" = allowed ]

# Isolation audit failure must refuse ANY core mutation without changing
# the already-valid core state.
export MOCK_ISOLATION=unsafe
if sh "$FW" sync >/dev/null 2>&1; then
    echo "ERROR: unsafe isolation audit allowed core sync" >&2
    exit 1
fi
[ "$(sh "$FW" inspect-reply)" = unavailable ]
[ "$(sh "$FW" inspect)" = allowed ]
export MOCK_ISOLATION=ok

# Opt-in reply observer: two independent no-verdict rules, no duplicate hooks.
sh "$FW" sync
[ "$(sh "$FW" inspect-reply)" = ready ]
[ "$(sh "$FW" sample-reply)" = '75 45000 30 12000' ]
# If the audit becomes unsafe, observer-only maintenance rolls back its
# own hooks without touching the valid core gate.
export MOCK_ISOLATION=unsafe
sh "$FW" sync-reply
[ "$(sh "$FW" inspect-reply)" = unavailable ]
[ "$(sh "$FW" inspect)" = allowed ]
export MOCK_ISOLATION=ok
sh "$FW" sync
[ "$(sh "$FW" inspect-reply)" = ready ]
sh "$FW" sync
python3 - "$TMP/state.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))["chains"]
pr=[r for r in c["PREROUTING"] if "TVG_RX_LAN" in r]
lo=[r for r in c["OUTPUT"] if "TVG_RX_LOCAL" in r]
assert len(pr)==1 and len(lo)==1,(pr,lo)
assert "-j" not in pr[0] and "-j" not in lo[0],(pr,lo)
assert len(c["PREROUTING"])==4 and len(c["OUTPUT"])==3,c
assert c["PREROUTING"][-2:]==[
    ["-s","203.0.113.5","-j","PROXY_RAW_A"],
    ["-d","198.51.100.8","-j","PROXY_RAW_B"],
],c
assert c["OUTPUT"][-2:]==[
    ["-d","203.0.113.6","-j","PROXY_OUT_A"],
    ["-s","198.51.100.9","-j","PROXY_OUT_B"],
],c
PY

sh "$FW" gate 1
[ "$(sh "$FW" inspect)" = blocked ]
# Passive hook recovery must not alter a blocked gate.
python3 - "$TMP/state.json" <<'PY'
import json,sys
p=sys.argv[1]
s=json.load(open(p))
s["chains"]["PREROUTING"]=[
    r for r in s["chains"]["PREROUTING"] if "TVG_RX_LAN" not in r]
s["chains"]["OUTPUT"]=[
    r for r in s["chains"]["OUTPUT"] if "TVG_RX_LOCAL" not in r]
json.dump(s,open(p,"w"))
PY
[ "$(sh "$FW" inspect)" = blocked ]
[ "$(sh "$FW" inspect-reply)" = unavailable ]
sh "$FW" sync-reply
[ "$(sh "$FW" inspect-reply)" = ready ]
[ "$(sh "$FW" inspect)" = blocked ]
sh "$FW" gate 0
[ "$(sh "$FW" inspect)" = allowed ]

# Even if someone sets enforce=1 without arming, FW3 reload remains permissive.
export MOCK_ENFORCE=1
export MOCK_ARMED=0
sh "$FW" sync
[ "$(sh "$FW" inspect)" = allowed ]

# Disabling the observer must remove ONLY its own two rules; keep the gate.
export MOCK_OBSERVE_REPLY=0
sh "$FW" sync
[ "$(sh "$FW" inspect-reply)" = disabled ]
[ "$(sh "$FW" inspect)" = allowed ]
python3 - "$TMP/state.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))["chains"]
assert all("TVG_RX_LAN" not in r for r in c["PREROUTING"]), c
assert all("TVG_RX_LOCAL" not in r for r in c["OUTPUT"]), c
PY
# Re-enable then uninstall to cover cleanup of both passive hooks.
export MOCK_OBSERVE_REPLY=1
sh "$FW" sync
sh "$FW" remove
[ "$(sh "$FW" inspect)" = absent ]
python3 - "$TMP/state.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))["chains"]
assert c=={
    "PREROUTING":[
        ["-s","203.0.113.5","-j","PROXY_RAW_A"],
        ["-d","198.51.100.8","-j","PROXY_RAW_B"],
    ],
    "OUTPUT":[
        ["-d","203.0.113.6","-j","PROXY_OUT_A"],
        ["-s","198.51.100.9","-j","PROXY_OUT_B"],
    ],
    "PROXY_RAW_A":[["-m","comment","--comment","existing_proxy_rule_a"]],
    "PROXY_RAW_B":[["-m","comment","--comment","existing_proxy_rule_b"]],
    "PROXY_OUT_A":[["-m","comment","--comment","existing_proxy_out_a"]],
    "PROXY_OUT_B":[["-m","comment","--comment","existing_proxy_out_b"]],
},c
PY
echo "PASS: gate, opt-in passive reply telemetry, duplicate avoidance, safety and isolated removal"
