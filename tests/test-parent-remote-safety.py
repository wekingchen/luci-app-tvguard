#!/usr/bin/env python3
"""家长遥控服务的权限和隔离静态回归。"""
import json
from pathlib import Path
p=Path(__file__).resolve().parent.parent
init=(p/"root/etc/init.d/tvguard-remote").read_text()
cgi=(p/"root/usr/share/tvguard-remote/www/cgi-bin/tvg").read_text()
read=(p/"root/usr/libexec/tvguard-remote-read").read_text()
manage=(p/"root/usr/libexec/tvguard-remote-manage").read_text()
frontend=(p/"root/usr/share/tvguard-remote/www/app.js").read_text()
acl=json.loads((p/"root/usr/share/rpcd/acl.d/luci-app-tvguard.json").read_text())["luci-app-tvguard"]
menu=json.loads((p/"root/usr/share/luci/menu.d/luci-app-tvguard.json").read_text())
assert "-p 127.0.0.1:18765" in init
assert "-h /usr/share/tvguard-remote/www" in init and "remote-enabled" in init
assert "/usr/libexec/tvguardctl" in cgi and "/usr/libexec/tvguard-status status" in cgi
for command in ("mode child","mode parent","mode locked","bonus 15","bonus 30","bonus 60","bonus undo"):
    assert command in cgi,command
assert "same_origin ||" in cgi and "HTTP_ORIGIN" in cgi
assert "HTTP_X_TVGUARD_ACTION" in cgi and "SameSite=Strict" in cgi
assert "HttpOnly" in cgi and "Max-Age=2592000" in cgi
assert "pair.lock" in cgi and 'rm -f "$PAIR"' in cgi
assert "sha256sum" in cgi and "new_random" in cgi
assert "status)" in read and "enable)" not in read
assert "enable|disable|pair|revoke-all)" in manage
assert acl["read"]["file"]["/usr/libexec/tvguard-remote-read"]==["exec"]
assert acl["write"]["file"]["/usr/libexec/tvguard-remote-manage"]==["exec"]
assert "/usr/libexec/tvguard-remote-admin" not in acl["read"]["file"]
assert "/usr/libexec/tvguard-remote-admin" not in acl["write"]["file"]
assert menu["admin/services/tvguard/remote"]["action"]["path"]=="tvguard/remote"
for unsafe in ("iptables ","nft ","uci set","docker ","eval ","ubus "):
    assert unsafe not in cgi,unsafe
assert "credentials: 'same-origin'" in frontend and "X-TVGuard-Action" in frontend
assert "window.confirm" in frontend
print("PASS: gated local-only remote PWA, CGI actions and ACL separation")
