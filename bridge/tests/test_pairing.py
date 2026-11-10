#!/usr/bin/env python3
"""End-to-end one-tap pairing contract: root-arms, fixed-TV-IP, single-use."""
import os
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cgi_src = (root / "root/www/cgi-bin/tvguard-agent").read_text()
admin_src = (root / "root/usr/libexec/tvguard-agent-bridge-pair").read_text()
token = "0123456789abcdef0123456789abcdef"

with tempfile.TemporaryDirectory(prefix="tvg-pair-") as path:
    d = Path(path)
    key = d / "key"
    key.write_text(token + "\n")
    runtime = d / "runtime"
    fake_uci = d / "uci"
    fake_uci.write_text('#!/bin/sh\nprintf "192.168.101.76\\n"\n')
    fake_uci.chmod(0o755)

    admin = d / "pair"
    admin.write_text(admin_src.replace(
        "/var/run/tvguard-agent-bridge", str(runtime)).replace(
        "/etc/tvguard/agent-bridge.key", str(key)))
    admin.chmod(0o755)
    cgi = d / "cgi"
    cgi.write_text(cgi_src.replace(
        "/var/run/tvguard-agent-bridge", str(runtime)).replace(
        "/etc/tvguard/agent-bridge.key", str(key)).replace(
        "uci -q get tvguard.main.ip", str(fake_uci) + " -q get tvguard.main.ip"))
    cgi.chmod(0o755)

    def arm(*args):
        result = subprocess.run(["dash", str(admin), *args],
                                text=True, capture_output=True, timeout=4)
        assert result.returncode == 0, (result.stdout, result.stderr)
        return result.stdout

    def post(body, remote="192.168.101.76"):
        env = {**os.environ, "REQUEST_METHOD": "POST", "REMOTE_ADDR": remote,
               "CONTENT_LENGTH": str(len(body.encode("ascii")))}
        result = subprocess.run(["dash", str(cgi)], input=body, text=True,
                                capture_output=True, env=env, timeout=5)
        assert result.returncode == 0, (result.stdout, result.stderr)
        return result.stdout

    assert "403 Forbidden" in post("PAIR1\n"), "unarmed auto-pairing must fail"
    assert "pairing_window=closed" in arm("status")
    assert "120" in arm("open")
    assert "pairing_window=open" in arm("status")

    assert "403 Forbidden" in post("PAIR1\n", "192.168.101.66")
    assert "pairing_window=open" in arm("status"), "unauthorized requester consumed pairing"

    # A valid request gets the key only once. Never includes token in URL.
    result = post("PAIR1\n")
    assert "Status: 200 OK" in result
    assert "TOKEN1|" + token + "\n" in result
    assert "Cache-Control: no-store" in result
    assert "403 Forbidden" in post("PAIR1\n"), "replay disclosed key again"
    assert "pairing_window=closed" in arm("status")

    arm("open")
    (runtime / "pair-window").write_text(str(int(time.time()) - 1) + "\n")
    assert "403 Forbidden" in post("PAIR1\n"), "expired pairing should fail"
    arm("close")

    # Standard continuous status reporting must remain backwards compatible.
    event = ("TVG1|" + token +
             "|1|com.gitvdemo.video|com.gala.video.app.player.PlayerActivity|1|1|1794319200000\n")
    assert "Status: 200 OK" in post(event)
    assert (runtime / "latest").exists()

print("N1 pairing: admin window, TV IP check, token, expiry, replay, normal status PASS")
