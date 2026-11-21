#!/usr/bin/env python3
"""Mock an N1 reflash and check safe /etc/tvguard symlink restoration."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "root/usr/libexec/tvguard-data").read_text()
OLD_KEY = "a" * 32
NEW_KEY = "b" * 32


def check(value, message):
    if not value:
        raise AssertionError(message)


def setup(where, mounted=True, persistent_key=OLD_KEY, overlay=True):
    root = Path(where)
    mount = root / "mmc"
    persistent = mount / "tvguard"
    legacy = root / "etc/tvguard"
    mounts = root / "mounts"
    script = root / "tvguard-data"
    persistent.mkdir(parents=True)
    (persistent / ".layout-v1").write_text("")
    (persistent / "remote-enabled").write_text("1\n")
    (persistent / "remote-lan-enabled").write_text("1\n")
    if persistent_key is not None:
        (persistent / "agent-bridge.key").write_text(persistent_key + "\n")
    if overlay:
        legacy.mkdir(parents=True)
        (legacy / "agent-bridge.key").write_text(NEW_KEY + "\n")
        (legacy / "remote-enabled").write_text("0\n")
        (legacy / "unknown-admin-file").write_text("must-keep")

    mounts.write_text(f"/dev/test {mount} xfs rw 0 0\n" if mounted else "")
    replacements = [
        ("/mnt/mmcblk2p4", str(mount)),
        ("/etc/tvguard", str(legacy)),
        ("/var/run/tvguard-data", str(root / "run/tvguard-data")),
        ("/proc/mounts", str(mounts)),
        ("/etc/config/tvguard", str(root / "etc/config/tvguard")),
        ("/usr/share/tvguard/default-config", str(root / "share/default-config")),
        ("/etc/.tvguard-config-v1", str(root / "etc/.tvguard-config-v1")),
    ]
    contents = SOURCE
    for original, replacement in replacements:
        contents = contents.replace(original, replacement)
    script.write_text(contents)
    return script, persistent, legacy


def prepare(script):
    return subprocess.run(
        ["dash", str(script), "prepare"], text=True, capture_output=True
    )


def test_ota_recovery():
    with tempfile.TemporaryDirectory(prefix="tvguard-ota-") as folder:
        script, persistent, legacy = setup(folder)
        result = prepare(script)
        check(result.returncode == 0, f"OTA recovery failed: {result.stderr}")
        check(legacy.is_symlink() and legacy.resolve() == persistent, "link not restored")
        check((legacy / "agent-bridge.key").read_text().strip() == OLD_KEY,
              "original TV pairing key changed")
        check((legacy / "remote-enabled").read_text().strip() == "1",
              "original remote consent not restored")
        check(not (legacy / "unknown-admin-file").exists(),
              "stale overlay contents were not removed")
        check(not list(persistent.glob(".overlay-etc-tvguard.*")),
              "OTA recovery unexpectedly created a backup")
        check(not list(legacy.parent.glob("tvguard.relink.*")),
              "OTA recovery unexpectedly left a parked overlay")
        check(prepare(script).returncode == 0, "repeated prepare is not idempotent")
        check(legacy.is_symlink() and legacy.resolve() == persistent,
              "repeated prepare changed persistent link")


def test_without_mount():
    with tempfile.TemporaryDirectory(prefix="tvguard-ota-") as folder:
        script, persistent, legacy = setup(folder, mounted=False)
        check(prepare(script).returncode == 0, "volatile fallback failed")
        check(not legacy.is_symlink(), "relinked while persistent mount was missing")
        check((legacy / "agent-bridge.key").read_text().strip() == NEW_KEY,
              "credentials changed without persistent mount")


def test_invalid_durable_key():
    with tempfile.TemporaryDirectory(prefix="tvguard-ota-") as folder:
        script, persistent, legacy = setup(folder, persistent_key="invalid")
        check(prepare(script).returncode != 0, "invalid stored identity accepted")
        check(legacy.is_dir() and not legacy.is_symlink(), "invalid key caused relink")


def test_new_install_with_existing_overlay():
    with tempfile.TemporaryDirectory(prefix="tvguard-ota-") as folder:
        script, persistent, legacy = setup(folder, persistent_key=None)
        check(prepare(script).returncode == 0, "fresh install fallback failed")
        check(legacy.is_dir() and not legacy.is_symlink(),
              "unknown existing overlay moved without durable identity")


def test_stale_upgrade_snapshot_cannot_overwrite_durable_key():
    """preinst may snapshot the regenerated overlay key before postinst relinks XFS."""
    with tempfile.TemporaryDirectory(prefix="tvguard-upgrade-") as folder:
        root = Path(folder)
        script, persistent, legacy = setup(root)
        check(prepare(script).returncode == 0, "initial OTA recovery failed")
        upgrade = root / "upgrade"
        upgrade.mkdir()
        snapshot = upgrade / "agent-bridge.key"
        snapshot.write_text(NEW_KEY + "\n")
        full_postinst = (ROOT / "ipkg/postinst").read_text()
        start = full_postinst.index("restore_upgrade_key() {")
        end = full_postinst.index("\n}\n", start) + 2
        valid_start = full_postinst.index("valid_key_file() {")
        valid_end = full_postinst.index("\n}\n", valid_start) + 2
        implementation = full_postinst[valid_start:valid_end] + "\n" + full_postinst[start:end]
        implementation = implementation.replace("/mnt/mmcblk2p4/tvguard", str(persistent))
        implementation = implementation.replace("/etc/tvguard", str(legacy))
        restore = root / "upgrade-restore"
        restore.write_text(
            "set -eu\nUPGRADE='" + str(upgrade) + "'\n" +
            "atomic_copy() { cp \"$1\" \"$2\"; }\n" +
            implementation + "\nrestore_upgrade_key\n"
        )
        completed = subprocess.run(
            ["dash", str(restore)], capture_output=True, text=True
        )
        check(completed.returncode == 0,
              "durable pairing key upgrade protection failed: " + completed.stderr)
        check((legacy / "agent-bridge.key").read_text().strip() == OLD_KEY,
              "preinst snapshot replaced the original paired TV identity")
        check(not snapshot.exists(), "stale snapshot not discarded")
        check(not list(persistent.glob(".overlay-etc-tvguard.*")),
              "unexpected XFS backup created during key restore")

def test_admin_symlink():
    with tempfile.TemporaryDirectory(prefix="tvguard-ota-") as folder:
        root = Path(folder)
        script, persistent, legacy = setup(folder, overlay=False)
        custom = root / "admin-storage"
        custom.mkdir()
        legacy.parent.mkdir(parents=True, exist_ok=True)
        legacy.symlink_to(custom)
        check(prepare(script).returncode != 0, "foreign symlink silently accepted")
        check(legacy.is_symlink() and legacy.resolve() == custom,
              "foreign administrator link modified")


if __name__ == "__main__":
    test_ota_recovery()
    test_without_mount()
    test_invalid_durable_key()
    test_new_install_with_existing_overlay()
    test_stale_upgrade_snapshot_cannot_overwrite_durable_key()
    test_admin_symlink()
    print("PASS: OTA restores original Agent key, remote consent and safe XFS link")
