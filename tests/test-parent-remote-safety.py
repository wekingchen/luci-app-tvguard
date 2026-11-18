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
assert 'procd_append_param command -p "$lan_ip:18765"' in init
assert "remote-lan-enabled" in init
assert "0.0.0.0:18765" not in init
lan_helper=(p/"root/usr/libexec/tvguard-remote-lan-ip").read_text()
assert "dev br-lan scope global" in lan_helper
assert "$1==192 && $2==168" in lan_helper
assert "$1==10" in lan_helper and "$1==172" in lan_helper
assert "enable-lan" in (p/"htdocs/luci-static/resources/view/tvguard/remote.js").read_text()
assert "client_allowed ||" in cgi and "ip -4 route get" in cgi
assert "-h /usr/share/tvguard-remote/www" in init and "remote-enabled" in init
assert "/usr/libexec/tvguardctl" in cgi and "/usr/libexec/tvguard-remote-status" in cgi
for command in ("mode child","mode parent","mode locked","bonus 15","bonus 30","bonus 60","bonus undo"):
    assert command in cgi,command
assert "same_origin ||" in cgi and "HTTP_ORIGIN" in cgi
assert "HTTP_REFERER" in cgi and "HTTP_HOST" in cgi
assert "SERVER_ADDR" in cgi and "DNS rebinding" in cgi
assert "HTTP_X_FORWARDED_PROTO" not in cgi
assert "secure='; Secure'" in cgi
assert 'name="referrer" content="same-origin"' in (p/"root/usr/share/tvguard-remote/www/index.html").read_text()
html=(p/"root/usr/share/tvguard-remote/www/index.html").read_text()
assert 'Content-Security-Policy' in html and "connect-src 'self'" in html
assert "object-src 'none'" in html and "base-uri 'none'" in html
assert 'app.js?v=0.1.16-r13' in html
assert "HTTP_X_TVGUARD_ACTION" in cgi and "SameSite=Strict" in cgi
assert '[ "$HTTP_X_TVGUARD_ACTION" = 1 ]' not in cgi
assert "HttpOnly" in cgi and "Max-Age=2592000" in cgi
assert "Path=/cgi-bin/tvg" in cgi
assert 'claim="$(mktemp "$PAIR.claim.XXXXXX")"' in cgi and 'mv -f "$PAIR" "$claim"' in cgi
assert 'trap \'rm -f "$claim"\' EXIT' in cgi
assert 'pair.lock' not in cgi
assert cgi.index("device_limit") < cgi.index('mv -f "$PAIR" "$claim"')
assert "new_random" in cgi and "tvguard-random-hex" in cgi
assert 'GENERATION="$ROOT/generation"' in cgi
assert '$3==gen' in cgi
assert 'rotate_generation' in (p/"root/usr/libexec/tvguard-remote-admin").read_text()
admin=(p/"root/usr/libexec/tvguard-remote-admin").read_text()
assert 'tvguard-random-hex "$1"' in admin
helper=(p/"root/usr/libexec/tvguard-random-hex").read_text()
assert "/dev/urandom" in helper and "sha256sum" in helper
assert "od -" not in helper and "xxd " not in helper and "hexdump " not in helper
assert "od -" not in cgi and "od -" not in admin
assert "status)" in read and "enable)" not in read
assert "enable|disable|enable-lan|disable-lan|pair|revoke-all)" in manage
assert acl["read"]["file"]["/usr/libexec/tvguard-remote-read"]==["exec"]
assert acl["write"]["file"]["/usr/libexec/tvguard-remote-manage"]==["exec"]
assert "/usr/libexec/tvguard-remote-admin" not in acl["read"]["file"]
assert "/usr/libexec/tvguard-remote-admin" not in acl["write"]["file"]
assert menu["admin/services/tvguard/remote"]["action"]["path"]=="tvguard/remote"
for unsafe in ("iptables ","nft ","uci set","docker ","eval ","ubus "):
    assert unsafe not in cgi,unsafe
assert "credentials: 'same-origin'" in frontend and "X-TVGuard-Action" not in frontend
assert "window.confirm" in frontend
print("PASS: gated local-only remote PWA, CGI actions and ACL separation")

assert 'id="reloadPage"' in html
assert "window.location.reload()" in frontend

assert 'index("," $4 ",", ",rw,")' in cgi
assert 'index(","$4",",rw,")' not in cgi
assert 'index("," $4 ",", ",rw,")' in admin
assert 'tmp="$(mktemp "$ROOT/generation.XXXXXX")"' in admin
assert 'pair_tmp="$(mktemp "$PAIR.tmp.XXXXXX")"' in admin
assert 'storage_ok() { [ -d "$ROOT" ]; }' not in (p/"tests/test-remote-cgi-e2e.py").read_text()
