#!/usr/bin/env python3
"""静态防回归检查：Cloudflare Tunnel 容器必须与 TVGuard 核心隔离。"""
from pathlib import Path
import json

root = Path(__file__).resolve().parent.parent
src = (root / "root/usr/libexec/tvguard-tunnel").read_text()
reader = (root / "root/usr/libexec/tvguard-tunnel-read").read_text()
writer = (root / "root/usr/libexec/tvguard-tunnel-manage").read_text()
page = (root / "htdocs/luci-static/resources/view/tvguard/tunnel.js").read_text()
acl = json.loads((root / "root/usr/share/rpcd/acl.d/luci-app-tvguard.json").read_text())
menu = json.loads((root / "root/usr/share/luci/menu.d/luci-app-tvguard.json").read_text())
conf = (root / "root/etc/config/tvguard").read_text()
permissions = acl["luci-app-tvguard"]

assert 'status|logs)' in reader and 'start)' not in reader
assert 'prepare|save-token|start|stop|restart|rebuild)' in writer
assert permissions["read"]["file"]["/usr/libexec/tvguard-tunnel-read"] == ["exec"]
assert "/usr/libexec/tvguard-tunnel-manage" not in permissions["read"]["file"]
assert permissions["write"]["file"]["/usr/libexec/tvguard-tunnel-manage"] == ["exec"]
assert permissions["write"]["file"]["/tmp/tvguard-tunnel/token.pending"] == ["write"]
assert "/usr/libexec/tvguard-tunnel" not in permissions["read"]["file"]
assert "/usr/libexec/tvguard-tunnel" not in permissions["write"]["file"]
assert "org.tvguard.owner=luci-app-tvguard" in src
assert "managed || die" in src
assert "container_exists" in src
assert "--token-file /etc/tvguard/token" in src
assert '--mount "type=bind,src=$DATA,dst=/etc/tvguard,readonly"' in src
assert "--metrics 127.0.0.1:20241" in src
assert 'docker rename' in src
assert "runAction('rebuild'" in page
assert "--cap-drop ALL" in src
assert "no-new-privileges:true" in src
assert "image inspect" in src and "docker pull" not in src
assert "storage_ready" in src and '"/mnt/mmcblk2p4"' in src
assert 'chmod 600 "$tmp"' in src and 'chmod 700 "$DATA"' in src
assert "fs.write(PENDING, value)" in page
assert 'PENDING_DIR=/tmp/tvguard-tunnel' in src
assert "var PENDING = '/tmp/tvguard-tunnel/token.pending'" in page
assert '/var/run/tvguard-tunnel' not in (src + page + str(permissions))
assert 'rpcd 文件 ACL' in page
assert "exec(MANAGE, ['prepare'])" in page
assert "exec(MANAGE, ['save-token'])" in page
assert "uci.set" not in page
assert "tunnel_token" not in conf
assert menu["admin/services/tvguard/tunnel"]["action"]["path"] == "tvguard/tunnel"
for unsafe in ("iptables ", "nft ", "uci set", "/etc/init.d/firewall", "docker rm", "docker pull"):
    assert unsafe not in src, f"unexpected privileged operation: {unsafe}"
print("PASS: Tunnel ACL separation, fixed container ownership, secret file and firewall isolation")
