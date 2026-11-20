#!/usr/bin/env python3
"""Host-side native staging parity test; full LEDE builds/N1 boots are separate."""
from __future__ import annotations

import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MAKEFILE = (ROOT / "Makefile").read_text()
VERSION = re.search(r"^PKG_VERSION:=(.+)$", MAKEFILE, re.M).group(1)
RELEASE = re.search(r"^PKG_RELEASE:=(.+)$", MAKEFILE, re.M).group(1)
PKG = ROOT / "dist" / f"luci-app-tvguard_{VERSION}-{RELEASE}_all.ipk"

def demand(ok: bool, why: str) -> None:
    if not ok:
        raise AssertionError(why)

def tar_files(blob: bytes) -> dict[str, bytes]:
    result = {}
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tf:
        for member in tf:
            if member.isfile():
                result[member.name.removeprefix("./")] = tf.extractfile(member).read()
    return result

def main() -> None:
    demand(PKG.is_file(), f"build scripts/build-ipk.sh first: {PKG}")
    demand("include $(INCLUDE_DIR)/package.mk" in MAKEFILE, "missing package.mk")
    demand("feeds/luci/luci.mk" not in MAKEFILE, "luci.mk shadows lifecycle hooks")
    for hook in ("preinst", "postinst", "prerm", "conffiles"):
        demand(f"$(file <$(CURDIR)/ipkg/{hook})" in MAKEFILE,
               f"native package does not reuse ipkg/{hook}")
    for field in ("CONFLICTS:=tvguard-agent-bridge", "PROVIDES:=tvguard-agent-bridge",
                  "PKGARCH:=all", "DEPENDS:=+luci-base +rpcd +curl +uhttpd +jsonfilter"):
        demand(field in MAKEFILE, f"missing native metadata: {field}")

    with tarfile.open(PKG, "r:gz") as outer:
        payload = tar_files(outer.extractfile("./data.tar.gz").read())
        control = tar_files(outer.extractfile("./control.tar.gz").read())
    for hook in ("preinst", "postinst", "prerm", "conffiles"):
        demand(control[hook] == (ROOT / "ipkg" / hook).read_bytes(),
               f"standalone control/{hook} drift")

    with tempfile.TemporaryDirectory(prefix="tvguard-native-") as temp:
        build = Path(temp) / "build"
        (build / "root").mkdir(parents=True)
        (build / "htdocs").mkdir()
        shutil.copytree(ROOT / "root", build / "root", dirs_exist_ok=True,
                        copy_function=shutil.copy2)
        shutil.copytree(ROOT / "htdocs", build / "htdocs", dirs_exist_ok=True,
                        copy_function=shutil.copy2)
        subprocess.run(["sh", str(ROOT / "scripts/stage-openwrt-native.sh"),
                        str(ROOT), str(build)], check=True)

        staged = {}
        for prefix, folder in (("", build / "root"), ("www/", build / "htdocs")):
            for path in folder.rglob("*"):
                if path.is_file():
                    staged[prefix + str(path.relative_to(folder))] = path.read_bytes()
        for path, contents in payload.items():
            demand(path in staged, f"native payload missing: {path}")
            demand(staged[path] == contents, f"native payload differs: {path}")
        extras = set(staged) - set(payload)
        expected = {
            "etc/uci-defaults/99-tvguard-native-init",
            "etc/init.d/tvguard-native-bootstrap",
            "usr/libexec/tvguard-package-postinst",
        }
        demand(extras == expected, f"unexpected native-only files: {extras ^ expected}")
        demand(staged["usr/libexec/tvguard-package-postinst"] ==
               (ROOT / "ipkg/postinst").read_bytes(), "native first-boot postinst drift")
        demand(staged["usr/libexec/tvguard-agent-bridge-setup"] ==
               (ROOT / "bridge/ipkg/postinst").read_bytes(), "Bridge setup drift")

        for entry in ("etc/init.d/tvguard", "etc/init.d/tvguard-agent-bridge",
                      "etc/init.d/tvguard-native-bootstrap",
                      "etc/uci-defaults/99-tvguard-native-init",
                      "usr/libexec/tvguard-package-postinst",
                      "usr/libexec/tvguard-agent-bridge-setup"):
            p = build / "root" / entry
            demand(p.is_file() and os.access(p, os.X_OK),
                   f"non-executable native entrypoint: {entry}")

        duplicate = build / "root/usr/libexec/tvguard-agent-fusion"
        original = duplicate.read_bytes()
        attempt = subprocess.run(
            ["sh", str(ROOT / "scripts/stage-openwrt-native.sh"), str(ROOT), str(build)],
            capture_output=True, text=True,
        )
        demand(attempt.returncode != 0 and "collision" in attempt.stderr,
               "duplicate native staging did not fail closed")
        demand(duplicate.read_bytes() == original, "duplicate changed file content")

    for script in ("scripts/stage-openwrt-native.sh",
                   "native/root/etc/uci-defaults/99-tvguard-native-init",
                   "native/root/etc/init.d/tvguard-native-bootstrap"):
        subprocess.run(["sh", "-n", str(ROOT / script)], check=True)
    print(f"Native staging parity OK ({len(payload)} main IPK files, {len(extras)} native-only files)")

if __name__ == "__main__":
    main()
