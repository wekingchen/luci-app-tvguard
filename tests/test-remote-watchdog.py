#!/usr/bin/env python3
"""Execute remote HTTP watchdog against a fake N1 daemon and probe responses.

These tests run the real POSIX shell (not a reimplementation) with isolated
state, mounted-XFS fixture, fake curl and mock /etc/init.d/tvguard-remote.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "root/usr/libexec/tvguard-remote-watchdog").read_text()
INIT = (ROOT / "root/etc/init.d/tvguard-remote-watchdog").read_text()
assert "USE_PROCD=1" in INIT
assert "START=98" in INIT
assert "procd_set_param command /usr/libexec/tvguard-remote-watchdog run" in INIT
assert "procd_set_param respawn" in INIT
assert "tvguard-remote restart" not in INIT  # only the watchdog tick may restart

with tempfile.TemporaryDirectory(prefix="tvguard-watchdog-") as tmp:
    root = Path(tmp)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    enabled = root / "enabled"
    lan_enabled = root / "lan-enabled"
    mock_lan_helper = root / "lan-helper"
    init = root / "tvguard-remote"
    action_log = root / "actions.log"
    syslog = root / "syslog"
    curl_loop = root / "loop.http"
    curl_lan = root / "lan.http"
    restore = root / "restore-on-restart"
    lan_ip = root / "lan-ip"
    mounts = root / "mounts"
    uptime = root / "uptime"
    state = root / "state"
    monitor = root / "watchdog"

    (bin_dir / "curl").write_text(
        "#!/bin/sh\n"
        "case \"$*\" in\n"
        "  *127.0.0.1:18765/cgi-bin/tvg*) cat \"$MOCK_LOOP\" ;;\n"
        "  *192.168.101.99:18765/*) cat \"$MOCK_LAN\" ;;\n"
        "  *) printf 000 ;;\n"
        "esac\n")
    (bin_dir / "logger").write_text(
        "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MOCK_LOG\"\n")
    mock_lan_helper.write_text(
        "#!/bin/sh\n[ -s \"$MOCK_LAN_IP\" ] || exit 1\ncat \"$MOCK_LAN_IP\"\n")
    init.write_text(
        "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"$MOCK_ACTIONS\"\n"
        "if [ \"$1\" = restart ] && [ -f \"$MOCK_RESTORE\" ]; then\n"
        "  printf 401 > \"$MOCK_LOOP\"\n"
        "  printf 200 > \"$MOCK_LAN\"\n"
        "fi\n")
    for x in [bin_dir / "curl", bin_dir / "logger", mock_lan_helper, init]:
        x.chmod(0o755)

    script = SOURCE
    for before, after in {
        "PATH=/usr/sbin:/usr/bin:/sbin:/bin":
            f"PATH={bin_dir}:/usr/bin:/bin",
        "ENABLED=/etc/tvguard/remote-enabled":f"ENABLED={enabled}",
        "LAN_ENABLED=/etc/tvguard/remote-lan-enabled":f"LAN_ENABLED={lan_enabled}",
        "LAN_HELPER=/usr/libexec/tvguard-remote-lan-ip":f"LAN_HELPER={mock_lan_helper}",
        "INIT=/etc/init.d/tvguard-remote":f"INIT={init}",
        "STATE_DIR=/var/run/tvguard-remote-watchdog":f"STATE_DIR={state}",
        "MOUNT=/mnt/mmcblk2p4":f"MOUNT={root / 'disk'}",
        "/proc/mounts":str(mounts),
        "/proc/uptime":str(uptime),
        "sleep 2":"sleep 0",
    }.items():
        assert before in script, before
        script = script.replace(before, after)
    monitor.write_text(script)
    monitor.chmod(0o755)
    env = dict(os.environ, MOCK_LOOP=str(curl_loop), MOCK_LAN=str(curl_lan),
               MOCK_ACTIONS=str(action_log), MOCK_RESTORE=str(restore),
               MOCK_LOG=str(syslog), MOCK_LAN_IP=str(lan_ip))

    def set_uptime(n):
        uptime.write_text(str(n) + ".00 0.00\n")

    def set_mount(ready):
        mounts.write_text(
            f"/dev/mmcblk2p4 {root / 'disk'} "
            f"{'xfs' if ready else 'ext4'} rw,relatime 0 0\n")

    def tick():
        proc = subprocess.run(["/bin/sh", str(monitor), "tick"], env=env,
                              capture_output=True, text=True, timeout=15)
        assert proc.returncode == 0, (proc.stdout, proc.stderr)
        return proc

    def restarts():
        return action_log.read_text().splitlines().count("restart")

    def reset():
        action_log.write_text("")
        syslog.write_text("")
        for x in [state / "failures", state / "last-restart"]:
            x.unlink(missing_ok=True)
        restore.unlink(missing_ok=True)

    enabled.write_text("1\n")
    lan_enabled.write_text("1\n")
    curl_loop.write_text("401")
    curl_lan.write_text("200")
    lan_ip.write_text("192.168.101.99\n")
    set_mount(True)
    set_uptime(200)
    reset()

    # Healthy service should remain untouched and make no log noise.
    for _ in range(3):
        tick()
    assert restarts() == 0
    assert syslog.read_text() == ""

    # Explicitly disabled by the parent: never re-enable, restart or probe.
    reset()
    enabled.write_text("0\n")
    curl_loop.write_text("000")
    for _ in range(3):
        tick()
    assert restarts() == 0
    enabled.write_text("1\n")

    # No false reboot recovery during initial grace or without mounted XFS.
    reset()
    set_uptime(100)
    tick()
    tick()
    assert restarts() == 0
    set_uptime(200)
    set_mount(False)
    tick()
    tick()
    assert restarts() == 0
    set_mount(True)

    # One bad sample is not enough. One healthy sample resets the streak.
    reset()
    curl_loop.write_text("000")
    tick()
    assert restarts() == 0 and (state / "failures").read_text().strip() == "1"
    curl_loop.write_text("401")
    tick()
    assert (state / "failures").read_text().strip() == "0"
    curl_loop.write_text("000")
    tick()
    assert restarts() == 0

    # Two consecutive failures trigger exactly one restart. Simulated service
    # recovery keeps old tokens, LAN configuration, and pairing files intact.
    restore.touch()
    tick()
    assert restarts() == 1, action_log.read_text()
    assert "自动恢复" in syslog.read_text()
    assert not (state / "lock").exists(), "lock must be released"
    assert (state / "last-restart").read_text().strip() == "200"

    # Never restart repeatedly inside the 10-minute cooldown, even if every
    # subsequent tick fails. After 600 monotonic seconds a retry is possible.
    restore.unlink()
    curl_loop.write_text("000")
    set_uptime(260)
    tick()
    set_uptime(320)
    tick()
    assert restarts() == 1
    set_uptime(810)
    tick()
    assert restarts() == 2, action_log.read_text()
    assert "冷却期" in syslog.read_text()

    # A blocked LAN HTTP listener alone is recoverable if br-lan has an IP.
    reset()
    set_uptime(1500)
    curl_loop.write_text("401")
    curl_lan.write_text("000")
    tick()
    tick()
    assert restarts() == 1, "LAN-only failure was not recovered"
    # Once LAN is intentionally disabled, its failing probe no longer matters.
    reset()
    lan_enabled.write_text("0\n")
    tick()
    tick()
    assert restarts() == 0
    lan_enabled.write_text("1\n")

    # netifd has no address yet. Restarting uhttpd cannot fix network
    # configuration; leave healthy loopback (and Cloudflare origin) intact.
    reset()
    lan_ip.write_text("")
    tick()
    tick()
    assert restarts() == 0
    lan_ip.write_text("192.168.101.99\n")

    # An already-held lock blocks concurrent tick execution. An abandoned
    # lock can be recovered after 120s of monotonic uptime.
    reset()
    lock = state / "lock"
    lock.mkdir()
    (lock / "started").write_text("1400\n")
    curl_loop.write_text("000")
    set_uptime(1500)
    tick()
    assert restarts() == 0
    assert (lock / "started").exists()
    set_uptime(1530)
    tick()
    assert not lock.exists(), "stale lock was not cleared"
    assert restarts() == 0  # only one actual failed sample so far
    tick()
    assert restarts() == 1

    # Nothing in the watchdog is allowed to manage other services.
    for forbidden in ("docker ", "iptables ", "nft ", "uci set",
                      "/etc/init.d/network", "/etc/init.d/firewall"):
        assert forbidden not in SOURCE, forbidden

print("PASS: remote watchdog two-strike HTTP recovery, boot/XFS/consent gates, cooldown, LAN-only failure, stale lock")
