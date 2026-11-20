#!/usr/bin/env python3
"""Exercise the actual procd init shell across cold-boot LAN races.

Runs with a fake procd interface and a delayed LAN-IP helper. Does not access
real N1 interfaces, firewall, TVGuard controls, or persistent data.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "root/etc/init.d/tvguard-remote").read_text()

with tempfile.TemporaryDirectory(prefix="tvg-remote-boot-") as d:
    root = Path(d)
    enabled = root / "remote-enabled"
    lan_enabled = root / "remote-lan-enabled"
    lan_helper = root / "lan-ip"
    uhttpd = root / "uhttpd"
    cgi = root / "tvg"
    log = root / "procd.log"
    counter = root / "counter"
    for p in (uhttpd, cgi):
        p.write_text("#!/bin/sh\nexit 0\n")
        p.chmod(0o755)
    enabled.write_text("1\n")
    lan_enabled.write_text("1\n")

    script = SOURCE.replace("/etc/tvguard/remote-enabled", str(enabled)).replace(
        "/etc/tvguard/remote-lan-enabled", str(lan_enabled)).replace(
        "/usr/sbin/uhttpd", str(uhttpd)).replace(
        "/usr/share/tvguard-remote/www/cgi-bin/tvg", str(cgi)).replace(
        "/usr/libexec/tvguard-remote-lan-ip", str(lan_helper)).replace(
        "/etc/init.d/tvguard-remote restart", str(root / "mock-init") + " restart")
    script = script.replace("sleep 1", "sleep 0")
    init = root / "init"
    init.write_text(script)
    init.chmod(0o755)

    harness = root / "harness.sh"
    harness.write_text("""#!/bin/sh
set -eu
record() { printf '%s\\n' "$*" >> "$TVG_PROCD_LOG"; }
procd_open_instance() { record 'instance-open'; }
procd_set_param() { record "param $*"; }
procd_append_param() { record "append $*"; }
procd_close_instance() { record 'instance-close'; }
procd_open_trigger() { record 'trigger-open'; }
procd_add_interface_trigger() { record "trigger $*"; }
procd_close_trigger() { record 'trigger-close'; }
logger() { :; }
. "$TVG_REMOTE_INIT"
start_service
service_triggers
""")
    harness.chmod(0o755)

    def write_helper(failures):
        # Count failures before making the private br-lan IPv4 available.
        counter.write_text("0\n")
        lan_helper.write_text(
            "#!/bin/sh\n"
            f"counter='{counter}'\n"
            "i=$(cat \"$counter\")\n"
            "i=$((i + 1))\n"
            "printf '%s\\n' \"$i\" > \"$counter\"\n"
            f"if [ \"$i\" -le {failures} ]; then exit 1; fi\n"
            "printf '%s\\n' 192.168.101.99\n"
        )
        lan_helper.chmod(0o755)

    def run():
        log.write_text("")
        env = dict(os.environ, TVG_PROCD_LOG=str(log), TVG_REMOTE_INIT=str(init))
        out = subprocess.run(["/bin/sh", str(harness)], env=env,
                             capture_output=True, text=True, timeout=8)
        return out, log.read_text()

    # 1. Worst case: br-lan does not have IPv4 even after bounded retries.
    #    Loopback must be registered, and netifd must have a recovery path.
    write_helper(999)
    result, events = run()
    assert result.returncode == 0, (result.stderr, events)
    assert "instance-close" in events, events
    assert "127.0.0.1:18765" in events, events
    assert "192.168.101.99:18765" not in events
    assert 'trigger interface.up lan ' in events, events
    assert 'trigger interface.update lan ' in events, events
    assert '0.0.0.0:18765' not in events

    # 2. The address becomes available after some retries.
    write_helper(3)
    result, events = run()
    assert result.returncode == 0, result.stderr
    assert "instance-close" in events
    assert "127.0.0.1:18765" in events
    assert "append command -p 192.168.101.99:18765" in events, events
    assert int(counter.read_text()) == 4, counter.read_text()

    # 3. Simulate a netifd interface.up/update restart after a delayed address
    #    appears: the subsequent start binds both loopback and LAN.
    write_helper(0)
    result, events = run()
    assert result.returncode == 0, result.stderr
    assert "append command -p 192.168.101.99:18765" in events

    # 4. LAN explicitly disabled: never bind LAN or register recovery trigger.
    lan_enabled.write_text("0\n")
    write_helper(0)
    result, events = run()
    assert result.returncode == 0, result.stderr
    assert "instance-close" in events
    assert "127.0.0.1:18765" in events
    assert "append command -p" not in events
    assert "trigger-open" not in events, events
    assert int(counter.read_text()) == 0

    # 5. Whole remote service disabled: do not start loopback nor resurrect it.
    enabled.write_text("0\n")
    result, events = run()
    assert result.returncode == 0, result.stderr
    assert events == "", events

print("PASS: cold-boot LAN race keeps loopback, rebinds on netifd recovery, respects disabled flags")
