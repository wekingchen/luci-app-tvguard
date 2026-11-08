#!/usr/bin/env python3
"""Repository-level proxy isolation audit.

The runtime firewall adapter is intentionally restricted to the raw table.
This audit fails CI if future changes attempt to manipulate proxy-sensitive
nat/mangle/filter tables, policy-routing state, global chains or proxy services.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FW = (ROOT / "root/usr/libexec/tvguard-fw").read_text(encoding="utf-8")
RUNTIME = []
for base in ("root/usr/libexec", "root/etc/init.d", "ipkg"):
    for path in (ROOT / base).rglob("*"):
        if path.is_file():
            RUNTIME.append((path, path.read_text(encoding="utf-8", errors="replace")))

errors = []

def require(cond, message):
    if not cond:
        errors.append(message)

# All actual iptables invocations must pass through one hardcoded raw wrapper.
require('raw_ipt() { "$IPT" -t raw "$@"; }' in FW,
        "tvguard-fw must expose exactly the raw-table wrapper")
direct_calls = [line.strip() for line in FW.splitlines()
                if '"$IPT"' in line and not line.strip().startswith("raw_ipt()")]
require(not direct_calls, f"direct iptables calls bypass raw_ipt: {direct_calls}")

# No proxy-sensitive table names or targets may appear in executable firewall code.
for token in (
    "-t nat", "-t mangle", "-t filter",
    "TPROXY", "REDIRECT", "DNAT", "SNAT", "MASQUERADE",
    "MARK", "CONNMARK", "NOTRACK", "CT --notrack",
):
    require(token not in FW, f"forbidden firewall token in tvguard-fw: {token}")

# No global-chain flush/delete. TV Guard may only flush/delete its own chains.
for line in FW.splitlines():
    stripped = line.strip()
    if not stripped.startswith("raw_ipt"):
        continue
    if re.search(r"\s-(F|X)\s+(PREROUTING|OUTPUT|INPUT|FORWARD)\b", stripped):
        errors.append(f"global built-in chain mutation forbidden: {stripped}")
    if re.search(r"\s-(P|Z)\b", stripped):
        errors.append(f"global policy/counter mutation forbidden: {stripped}")

# Runtime scripts must not reconfigure or restart existing proxy stacks.
proxy_words = (
    "openclash", "passwall", "shadowsocks", "shadowsocksr",
    "ssrplus", "v2ray", "xray", "sing-box",
)
for path, text in RUNTIME:
    lower = text.lower()
    for word in proxy_words:
        if word in lower:
            errors.append(f"{path.relative_to(ROOT)} mentions proxy service '{word}'")
    # No policy routing or network sysctl writes from TV Guard runtime.
    dangerous = (
        r"\bip\s+rule\s+(add|del|replace)",
        r"\bip\s+route\s+(add|del|replace|flush)",
        r"\bsysctl\s+-w\b",
        r"/proc/sys/net/",
        r"\bebtables\b",
        r"\bnft\b",
        r"iptables-restore",
    )
    for pattern in dangerous:
        if re.search(pattern, text):
            errors.append(f"{path.relative_to(ROOT)} contains forbidden runtime operation: {pattern}")

# Package scripts may add/delete only their own firewall include section and must
# not restart/reload the global firewall or proxy services.
postinst = (ROOT / "ipkg/postinst").read_text(encoding="utf-8")
prerm = (ROOT / "ipkg/prerm").read_text(encoding="utf-8")
for name, text in (("postinst", postinst), ("prerm", prerm)):
    for line in text.splitlines():
        if "uci set firewall." in line:
            require("firewall.tvguard" in line,
                    f"{name} may only write firewall.tvguard: {line.strip()}")
    require("/etc/init.d/firewall restart" not in text and
            "/etc/init.d/firewall reload" not in text,
            f"{name} must not restart/reload global firewall")

# The optional reply observer itself must be target-free.
require('TVG_RX_LAN' in FW and 'TVG_RX_LOCAL' in FW,
        "reply observer markers missing")
for line in FW.splitlines():
    if "TVG_RX_LAN" in line or "TVG_RX_LOCAL" in line:
        if "raw_ipt" in line and (" -A " in line or " -I " in line):
            require(" -j " not in line,
                    f"reply observation rule has a verdict/target: {line.strip()}")

if errors:
    for error in errors:
        print("FAIL:", error, file=sys.stderr)
    raise SystemExit(1)

print("PASS: raw-only firewall adapter; no proxy-table, policy-route, global-chain or proxy-service mutation")
