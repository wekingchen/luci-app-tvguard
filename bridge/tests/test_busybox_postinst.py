#!/usr/bin/env python3
"""Exercise the real postinst on a BusyBox-like command path without od.

All installed file targets are rewritten to a temporary sandbox.
"""
import os
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
original = (root / "ipkg/postinst").read_text()
assert "od -An" not in original

with tempfile.TemporaryDirectory(prefix="tvguard-install-test-") as directory:
    sandbox = Path(directory)
    key_dir = sandbox / "etc/tvguard"
    key_dir.mkdir(parents=True)
    key = key_dir / "agent-bridge.key"
    service = sandbox / "etc/init.d/tvguard-agent-bridge"
    cgi = sandbox / "www/cgi-bin/tvguard-agent"
    report = sandbox / "usr/libexec/tvguard-agent-bridge-report"
    soak = sandbox / "usr/libexec/tvguard-agent-bridge-soak"
    pair = sandbox / "usr/libexec/tvguard-agent-bridge-pair"
    billing = sandbox / "usr/libexec/tvguard-agent-billing-hint"
    fusion = sandbox / "usr/libexec/tvguard-agent-fusion"
    service_log = sandbox / "service.log"
    for path in (service, cgi, report, soak, pair, billing, fusion):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n")
        path.chmod(0o755)
    service.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$SERVICE_LOG"\n')

    mappings = [
        ("/etc/tvguard", str(key_dir)),
        ("/www/cgi-bin/tvguard-agent", str(cgi)),
        ("/usr/libexec/tvguard-agent-bridge-report", str(report)),
        ("/usr/libexec/tvguard-agent-bridge-soak", str(soak)),
        ("/usr/libexec/tvguard-agent-bridge-pair", str(pair)),
        ("/usr/libexec/tvguard-agent-billing-hint", str(billing)),
        ("/usr/libexec/tvguard-agent-fusion", str(fusion)),
        ("/etc/init.d/tvguard-agent-bridge", str(service)),
        ("/tmp/tvguard-agent-seed.", str(sandbox / "seed.")),
    ]
    script = original
    for old, new in mappings:
        script = script.replace(old, new)
    installer = sandbox / "postinst"
    installer.write_text(script)

    # Exactly required shell commands, explicitly excluding od.
    bin_dir = sandbox / "minimal-bin"
    bin_dir.mkdir()
    for command in ("dd", "sha256sum", "mktemp", "wc", "tr", "cut",
                    "chmod", "mkdir", "mv", "rm"):
        system_binary = shutil.which(command)
        assert system_binary, f"CI missing required simulator command: {command}"
        (bin_dir / command).symlink_to(system_binary)
    assert not (bin_dir / "od").exists()

    env = {**os.environ, "PATH": str(bin_dir), "SERVICE_LOG": str(service_log)}
    def run_install():
        p = subprocess.run(["/bin/dash", str(installer)], env=env,
                           text=True, capture_output=True, timeout=15)
        assert p.returncode == 0, (p.stdout, p.stderr)
        assert "learned player Activity is protected" in p.stdout

    # 0.2.0 failed install could create a newline-only key.
    key.write_text("\n")
    run_install()
    first = key.read_text().strip()
    assert re.fullmatch(r"[0-9a-f]{32}", first)
    assert stat.S_IMODE(key.stat().st_mode) == 0o600
    assert service_log.read_text().splitlines() == ["enable", "start"]
    assert not list(sandbox.glob("seed.*")), "random temporary seed leaked"
    assert not list(key_dir.glob(".agent-bridge-key.*")), "temporary key leaked"

    # Re-install must preserve previously valid pairing.
    run_install()
    assert key.read_text().strip() == first
    assert service_log.read_text().splitlines() == ["enable", "start", "enable", "start"]

    # Corrupted keys should be replaced, not silently retained.
    key.write_text("garbled")
    run_install()
    repaired = key.read_text().strip()
    assert re.fullmatch(r"[0-9a-f]{32}", repaired)
    assert repaired != first
    assert stat.S_IMODE(key.stat().st_mode) == 0o600

print("postinst BusyBox no-od + bad key recovery + idempotence + 0600 PASS")
