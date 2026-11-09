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
    "Depends: luci-base, rpcd",
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
    "usr/share/tvguard/default-config",
    "www/luci-static/resources/view/tvguard/overview.js",
):
    if name not in data:
        raise SystemExit(f"FAIL: missing installed file {name}")
    if name.startswith("usr/libexec/") or name == "etc/init.d/tvguard":
        assert data[name][0].mode & 0o111, f"{name} is not executable"
print(f"PASS: OpenWrt gzip-tar IPK, root ownership, package metadata, control and payload ({len(raw)} bytes)")
