#!/usr/bin/env python3
"""Reject malformed OpenWrt IPKs, even when archive creation itself succeeds."""
import io
import os
import sys
import tarfile
from pathlib import Path

if len(sys.argv) not in (3, 4):
    raise SystemExit("usage: verify-ipk.py PATH VERSION [RELEASE]")
path = Path(sys.argv[1])
version = sys.argv[2]
release = sys.argv[3] if len(sys.argv) == 4 else "1"
raw = path.read_bytes()
if raw[:2] != b"\x1f\x8b":
    raise SystemExit("FAIL: outer archive must be gzip-tar, not GNU ar/Debian .deb")
if raw.startswith(b"!<arch>"):
    raise SystemExit("FAIL: OpenWrt opkg compatibility: ar outer archive forbidden")


def check_tar(payload, description):
    tar = tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz")
    files = {}
    for member in tar.getmembers():
        if member.uid != 0 or member.gid != 0:
            raise SystemExit(f"FAIL: {description}: {member.name} not owned by root")
        # Ignore ./; all remaining entries are relative.
        n = member.name.removeprefix("./")
        if n.startswith("/") or n == ".." or "../" in n:
            raise SystemExit(f"FAIL: {description}: unsafe path {n}")
        if member.isfile():
            files[n] = (member, tar.extractfile(member).read())
    return files


outer = check_tar(raw, "outer")
assert set(outer) == {"debian-binary", "control.tar.gz", "data.tar.gz"}, sorted(outer)
assert outer["debian-binary"][1] == b"2.0\n"
control = check_tar(outer["control.tar.gz"][1], "control")
data = check_tar(outer["data.tar.gz"][1], "data")

metadata = control["control"][1].decode("utf-8")
for field in (
    "Package: luci-app-tvguard",
    f"Version: {version}-{release}",
    "Architecture: all",
    "Depends: luci-base, rpcd, curl, uhttpd, jsonfilter",
    "Conflicts: tvguard-agent-bridge",
    "Replaces: tvguard-agent-bridge",
    "Provides: tvguard-agent-bridge",
):
    if field not in metadata.splitlines():
        raise SystemExit(f"FAIL: missing opkg metadata {field}")
for name in ("preinst", "postinst", "prerm"):
    assert control[name][0].mode & 0o111, f"{name} is not executable"
for name in (
    "etc/config/tvguard",
    "etc/init.d/tvguard",
    "usr/libexec/tvguardctl",
    "usr/libexec/tvguardd",
    "usr/libexec/tvguard-fw",
    "usr/libexec/tvguard-isolation-audit",
    "usr/libexec/tvguard-compat-check",
    "usr/libexec/tvguard-shadow",
    "usr/libexec/tvguard-learn",
    "usr/libexec/tvguard-adaptive",
    "usr/libexec/tvguard-retention",
    "usr/libexec/tvguard-data",
    "usr/libexec/tvguard-soak",
    "usr/libexec/tvguard-soak-report",
    "usr/libexec/tvguard-daily-report",
    "usr/libexec/tvguard-remote-admin",
    "usr/libexec/tvguard-remote-status",
    "usr/libexec/tvguard-remote-read",
    "usr/libexec/tvguard-remote-manage",
    "usr/libexec/tvguard-remote-lan-ip",
    "usr/libexec/tvguard-random-hex",
    "etc/init.d/tvguard-remote",
    "usr/share/tvguard-remote/www/cgi-bin/tvg",
    "usr/share/tvguard-remote/www/index.html",
    "usr/share/tvguard-remote/www/app.js",
    "usr/share/tvguard-remote/www/style.css",
    "usr/share/tvguard-remote/www/manifest.webmanifest",
    "usr/share/tvguard-remote/www/icon.svg",
    "www/luci-static/resources/view/tvguard/remote.js",
    "www/luci-static/resources/view/tvguard/panel.css",
    "usr/libexec/tvguard-tunnel",
    "usr/libexec/tvguard-tunnel-read",
    "usr/libexec/tvguard-tunnel-manage",
    "etc/init.d/tvguard-agent-bridge",
    "usr/libexec/tvguard-agent-bridge-setup",
    "usr/libexec/tvguard-agent-billing-hint",
    "usr/libexec/tvguard-agent-bridge-pair",
    "usr/libexec/tvguard-agent-bridge-report",
    "usr/libexec/tvguard-agent-bridge-soak",
    "usr/libexec/tvguard-agent-fusion",
    "www/cgi-bin/tvguard-agent",
    "usr/share/tvguard/default-config",
    "www/luci-static/resources/view/tvguard/overview.js",
    "www/luci-static/resources/view/tvguard/tunnel.js",
):
    if name not in data:
        raise SystemExit(f"FAIL: missing installed file {name}")
    if name.startswith("usr/libexec/") or name.startswith("etc/init.d/") or name.startswith("www/cgi-bin/") or name == "usr/share/tvguard-remote/www/cgi-bin/tvg":
        assert data[name][0].mode & 0o111, f"{name} is not executable"
# Protect iPhone standalone Web App updates from accidental reused asset URLs.
# The initial r17 candidate and its later status-label fix shared the same
# app.js query key, so iOS could continue displaying old Cloudflare Tunnel text.
index_html = data["usr/share/tvguard-remote/www/index.html"][1].decode("utf-8")
app_js = data["usr/share/tvguard-remote/www/app.js"][1].decode("utf-8")
pwa_css = data["usr/share/tvguard-remote/www/style.css"][1].decode("utf-8")
assert "--line: rgba(127,127,127,.42)" in pwa_css, "overview-aligned Web App panel border missing from IPK"
assert "--tile-line: rgba(127,127,127,.32)" in pwa_css, "overview-aligned Web App metric border missing from IPK"
assert "--soft: rgba(127,127,127,.08)" in pwa_css, "overview-aligned Web App metric background missing from IPK"
assert ".progress.is-unlimited { display: none; }" in pwa_css, "parent progress visibility regressed"
assert "min-height: 44px" in pwa_css and "max(88px" in pwa_css, "Web App tap targets or safe area regressed"
assert "@media (prefers-color-scheme: dark)" in pwa_css, "Web App dark mode missing"

# Integration tests deliberately build current source with a historical package
# metadata version (0.1.15-11). Asset URLs must follow the actual source
# revision from Makefile, not the test's synthetic package control version.
import re
makefile = (Path(__file__).resolve().parents[1] / "Makefile").read_text()
source_version = re.search(r"^PKG_VERSION:=(\S+)$", makefile, re.M)
source_release = re.search(r"^PKG_RELEASE:=(\d+)$", makefile, re.M)
assert source_version and source_release, "source package revision missing"
asset_version = f"{source_version.group(1)}-r{source_release.group(1)}"
for asset in ("style.css", "app.js"):
    expected_url = f"/{asset}?v={asset_version}"
    assert expected_url in index_html, f"stale PWA asset key: expected {expected_url}"
assert "const label = path === 'Cloudflare Tunnel' ? '远程连接' : path;" in app_js, "short remote label missing"
assert "label + ' · ' + state" in app_js, "consistent connection-status format missing"
assert "远程连接正常" not in app_js, "legacy remote-only online label must not remain"
# Verify the actual installed LuCI payload, not only the source snapshot.
luci_css = data["www/luci-static/resources/view/tvguard/panel.css"][1].decode("utf-8")
luci_remote = data["www/luci-static/resources/view/tvguard/remote.js"][1].decode("utf-8")
luci_tunnel = data["www/luci-static/resources/view/tvguard/tunnel.js"][1].decode("utf-8")
luci_settings = data["www/luci-static/resources/view/tvguard/settings.js"][1].decode("utf-8")
luci_overview = data["www/luci-static/resources/view/tvguard/overview.js"][1].decode("utf-8")
assert "color: #f7faff !important" in luci_css, "dark pairing code contrast missing from IPK"
assert "background: transparent !important" in luci_css, "theme header reset missing from IPK"
assert "max-width: 980px" in luci_css and "background: transparent; box-shadow: none" in luci_css, "overview-aligned shared LuCI shell missing"
assert ".tvg-settings-root .cbi-section" in luci_css, "native settings form theming missing"
assert ".tvg-panel{margin:0 0 14px;padding:15px;" in luci_overview, "overview design baseline unexpectedly changed"
for view_source in (luci_remote, luci_tunnel, luci_settings):
    assert f"STYLE + '?v={asset_version}'" in view_source, "LuCI CSS cache version mismatch"
    assert "'aria-level': '1'" in view_source, "accessible page heading missing"
for view_source in (luci_remote, luci_tunnel):
    assert "'role': 'heading', 'aria-level': '2'" in view_source, "accessible card headings missing"

# HTTP/2 transport must be present in the actual package and must not
# silently reuse a legacy QUIC connector on N1 after opkg upgrade.
tunnel_script = data["usr/libexec/tvguard-tunnel"][1].decode("utf-8")
postinst_script = control["postinst"][1].decode("utf-8")
assert "--protocol http2" in tunnel_script, "Tunnel connector must use HTTP/2"
assert 'docker rename "$NAME" "$ROLLBACK"' in tunnel_script, "Tunnel migration backup missing"
assert "wait_for_http2_edge" in tunnel_script, "HTTP/2 handshake gate missing"
assert "restore_previous" in tunnel_script, "old tunnel rollback missing"
assert '"transport":"%s"' in tunnel_script, "Tunnel transport must be reported"
assert "docker container inspect tvguard-cloudflared" in postinst_script, "upgrade transport migration missing"
assert "org.tvguard.owner" in postinst_script, "upgrade migration ownership check missing"
luci_tunnel_expected = data["www/luci-static/resources/view/tvguard/tunnel.js"][1].decode("utf-8")
assert "HTTP/2（TCP 7844）" in luci_tunnel_expected, "configured transport indicator missing from LuCI"

assert "etc/tvguard/agent-bridge.key" not in data, "key must never be packaged"
assert "conffiles" in control and b"agent-bridge.key" not in control["conffiles"][1]
print(f"PASS: OpenWrt gzip-tar IPK, root ownership, package metadata, control and payload ({len(raw)} bytes)")
