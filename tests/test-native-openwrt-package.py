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
    demand("ln -snf ../init.d/tvguard-native-bootstrap" in MAKEFILE,
           "native rootfs must pre-enable bootstrap before rcS enumerates services")
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
    # Execute the actual Makefile prepare/install recipes with OpenWrt's
    # relevant make macros mocked. This catches syntax, bad copy paths and
    # missing rcS symlinks that direct staging comparison cannot detect.
    with tempfile.TemporaryDirectory(prefix="tvguard-make-") as temp:
        top = Path(temp)
        (top / "include").mkdir()
        (top / "rules.mk").write_text(
            "INCLUDE_DIR := $(TOPDIR)/include\n"
            "PKG_BUILD_DIR := $(TOPDIR)/build\n"
            "INSTALL_DIR := install -d\n"
            "CP := cp -fpR\n"
            "SHELL := /usr/bin/env bash\n"
        )
        (top / "include/package.mk").write_text("define BuildPackage\nendef\n")
        recipes = top / "native-recipes.mk"
        recipes.write_text(
            "export MOCK_PREINST = $(call Package/luci-app-tvguard/preinst)\n"
            "export MOCK_POSTINST = $(call Package/luci-app-tvguard/postinst)\n"
            "export MOCK_PRERM = $(call Package/luci-app-tvguard/prerm)\n"
            "export MOCK_CONFFILES = $(call Package/luci-app-tvguard/conffiles)\n"
            ".PHONY: native-recipes\n"
            "native-recipes:\n"
            "\t$(Build/Prepare)\n"
            "\t$(call Package/luci-app-tvguard/install,$(TOPDIR)/image)\n"
            "\t@echo \"$MOCK_PREINST\" > \"$(TOPDIR)/native-preinst\"\n"
            "\t@echo \"$MOCK_POSTINST\" > \"$(TOPDIR)/native-postinst\"\n"
            "\t@echo \"$MOCK_PRERM\" > \"$(TOPDIR)/native-prerm\"\n"
            "\t@echo \"$MOCK_CONFFILES\" > \"$(TOPDIR)/native-conffiles\"\n"
        )
        subprocess.run(
            ["make", "--no-print-directory", "-C", str(ROOT),
             "-f", "Makefile", "-f", str(recipes), "native-recipes",
             f"TOPDIR={top}"],
            capture_output=True, text=True, check=True,
        )
        image = top / "image"
        link = image / "etc/rc.d/S94tvguard-native-bootstrap"
        demand(link.is_symlink() and os.readlink(link) ==
               "../init.d/tvguard-native-bootstrap",
               "native rootfs bootstrap is not enabled before rcS startup")
        for path, contents in payload.items():
            mounted = image / path
            demand(mounted.is_file() and mounted.read_bytes() == contents,
                   f"actual Makefile install dropped/changed: {path}")
        for hook in ("preinst", "postinst", "prerm", "conffiles"):
            demand((top / f"native-{hook}").read_bytes() ==
                   (ROOT / "ipkg" / hook).read_bytes(),
                   f"Makefile lifecycle script expansion changed ipkg/{hook}")

    print(f"Native staging parity OK ({len(payload)} main IPK files, {len(extras)} native-only files)")

if __name__ == "__main__":
    main()
