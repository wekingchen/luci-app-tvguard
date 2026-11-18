#!/usr/bin/env python3
"""Execute TVGuard Tunnel lifecycle against a stateful fake Docker CLI.

Covers fresh HTTP/2 startup, migration of an existing QUIC connector, rollback
after an unregistered edge, foreign-container isolation and idempotent restart.
No host Docker daemon or real Tunnel token is accessed.
"""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "root/usr/libexec/tvguard-tunnel").read_text()
NAME = "tvguard-cloudflared"
BACKUP = "tvguard-cloudflared-before-http2"
IMAGE = "cloudflare/cloudflared:latest"

FAKE_DOCKER = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

store = Path(os.environ["TVG_FAKE_DOCKER"])
state = json.loads(store.read_text())
args = sys.argv[1:]
name = "tvguard-cloudflared"
success = True
output = ""

def container(ref):
    return state["containers"].get(ref)

def save():
    store.write_text(json.dumps(state))

def record(event):
    state["actions"].append(event)

if not args:
    success = False
elif args[0] == "info":
    pass
elif args[:2] == ["image", "inspect"]:
    success = True
elif args[:2] == ["container", "inspect"]:
    success = container(args[2]) is not None
elif args[0] == "inspect":
    if "-f" not in args:
        success = False
    else:
        fmt = args[args.index("-f") + 1]
        c = container(args[-1])
        if c is None:
            success = False
        elif ".State.Running" in fmt:
            output = "true" if c["running"] else "false"
        elif ".State.Status" in fmt:
            output = "running" if c["running"] else "exited"
        elif ".Config.Cmd" in fmt:
            output = json.dumps(c["cmd"], separators=(",", ":"))
        elif "org.tvguard.owner" in fmt:
            output = c["owner"]
        else:
            success = False
elif args[0] == "run":
    if args[1:4] == ["--rm", "--network", "none"]:
        output = "cloudflared version 2026.10.7 (built 2026-10-30)"
    else:
        if "--name" not in args:
            success = False
        else:
            dest = args[args.index("--name") + 1]
            if container(dest):
                success = False
            else:
                image_pos = args.index("cloudflare/cloudflared:latest")
                cmd = args[image_pos + 1:]
                state["containers"][dest] = {
                    "owner": "luci-app-tvguard", "running": True,
                    "cmd": cmd, "image": args[image_pos]
                }
                record({"op":"run","dest":dest,"args":args})
elif args[0] == "logs":
    c = container(args[-1])
    if c is None:
        success = False
    elif state["edge_ok"] and c["running"] and "--protocol" in c["cmd"] and "http2" in c["cmd"]:
        output = "INF Registered tunnel connection connIndex=0 location=lax01 protocol=http2"
elif args[0] in ("start", "stop", "restart"):
    c = container(args[1])
    if c is None:
        success = False
    else:
        c["running"] = args[0] != "stop"
        record({"op":args[0],"dest":args[1]})
elif args[0] == "rename":
    old, new = args[1:3]
    if old not in state["containers"] or new in state["containers"]:
        success = False
    else:
        state["containers"][new] = state["containers"].pop(old)
        record({"op":"rename","old":old,"new":new})
elif args[0] == "rm":
    ref = args[1]
    if ref not in state["containers"] or state["containers"][ref]["running"]:
        success = False
    else:
        del state["containers"][ref]
        record({"op":"rm","dest":ref})
else:
    success = False

save()
if output:
    print(output)
sys.exit(0 if success else 1)
'''

def old_container(owner="luci-app-tvguard", running=True):
    return {
        "owner": owner,
        "running": running,
        "cmd": ["tunnel", "--no-autoupdate", "--metrics",
                "127.0.0.1:20241", "run", "--token-file",
                "/etc/tvguard/token"],
        "image": IMAGE,
    }

def run_scenario(name, containers, edge_ok, verb="start"):
    with tempfile.TemporaryDirectory(prefix="tvg-http2-") as tmp:
        root = Path(tmp)
        bindir = root / "bin"
        bindir.mkdir()
        fake = bindir / "docker"
        fake.write_text(FAKE_DOCKER)
        fake.chmod(0o755)
        mount = root / "xfs"
        token_dir = mount / NAME
        token_dir.mkdir(parents=True)
        secret = token_dir / "token"
        secret.write_text("a"*128)
        secret.chmod(0o600)
        script = root / "tvguard-tunnel"
        code = SOURCE.replace("PATH=/usr/sbin:/usr/bin:/sbin:/bin",
                              f"PATH={bindir}:/usr/bin:/bin")
        code = code.replace("MOUNT=/mnt/mmcblk2p4", f"MOUNT={mount}")
        code, n = re.subn(r"storage_ready\(\) \{\n.*?\n\}",
                          "storage_ready() { return 0; }", code, count=1, flags=re.S)
        assert n == 1, "could not replace mount check in test fixture"
        code = code.replace('while [ "$attempts" -lt 20 ]',
                            'while [ "$attempts" -lt 1 ]')
        code = code.replace("sleep 2", "sleep 0")
        script.write_text(code)
        script.chmod(0o755)
        state_file = root / "docker.json"
        state_file.write_text(json.dumps({
            "containers": containers,
            "edge_ok": edge_ok,
            "actions": []
        }))
        env = dict(os.environ, TVG_FAKE_DOCKER=str(state_file))
        result = subprocess.run(
            ["/bin/sh", str(script), verb],
            env=env, capture_output=True, text=True, timeout=12,
        )
        state = json.loads(state_file.read_text())
        assert secret.read_text() == "a"*128, name + ": token was modified"
        return result, state

def assert_http2(container):
    cmd = container["cmd"]
    assert "--protocol" in cmd and cmd[cmd.index("--protocol")+1] == "http2", cmd
    assert cmd[-2:] == ["--token-file", "/etc/tvguard/token"], cmd
    assert "--metrics" in cmd and "127.0.0.1:20241" in cmd, cmd

unrelated = {
    "owner": "another-app", "running": True,
    "cmd": ["tunnel", "run"], "image": IMAGE
}
# New install preserves the entire existing container security contract.
result, state = run_scenario("fresh", {"vaultwarden-cloudflared": unrelated}, True)
assert result.returncode == 0, result.stderr
assert_http2(state["containers"][NAME])
args = next(x["args"] for x in state["actions"] if x["op"] == "run")
for expected in [
    "--restart", "unless-stopped", "--network", "host", "--cap-drop", "ALL",
    "--security-opt", "no-new-privileges:true", "--mount",
    "type=bind,src=", "dst=/etc/tvguard,readonly",
]:
    assert expected in " ".join(args), expected
assert state["containers"]["vaultwarden-cloudflared"] == unrelated

# Upgrading a running old QUIC container is transactional.
result, state = run_scenario("migrate", {
    NAME: old_container(), "ntfy_cloudflared": unrelated
}, True)
assert result.returncode == 0, result.stderr
assert_http2(state["containers"][NAME])
assert state["containers"][NAME]["running"]
assert BACKUP not in state["containers"]
assert state["containers"]["ntfy_cloudflared"] == unrelated
assert [x["op"] for x in state["actions"]] == [
    "stop", "rename", "run", "rm"
], state["actions"]

# A running new container is not enough: if no edge has registered,
# the original command and running state must be fully restored.
result, state = run_scenario("rollback", {NAME: old_container()}, False, "restart")
assert result.returncode != 0
assert "已恢复旧 Tunnel" in result.stderr
assert state["containers"][NAME] == old_container(), state
assert BACKUP not in state["containers"]
assert [x["op"] for x in state["actions"]] == [
    "stop", "rename", "run", "stop", "rm", "rename", "start"
], state["actions"]

# A foreign same-name container must never be modified.
foreign = old_container(owner="not-tvguard")
result, state = run_scenario("foreign", {NAME: foreign}, True)
assert result.returncode != 0
assert state["containers"][NAME] == foreign
assert state["actions"] == []

# A pre-existing rollback name must be preserved, not overwritten/deleted.
result, state = run_scenario("collision", {
    NAME: old_container(), BACKUP: old_container(running=False)
}, True)
assert result.returncode != 0
assert state["actions"] == []
assert state["containers"][NAME] == old_container()

# Starting an HTTP/2 instance again is a no-op; restarting keeps the same
# container identity (no token or pairing reset).
http2 = old_container()
http2["cmd"][2:2] = ["--protocol", "http2"]
result, state = run_scenario("idempotent", {NAME: http2}, True)
assert result.returncode == 0, result.stderr
assert state["actions"] == []
result, state = run_scenario("restart-http2", {NAME: http2}, True, "restart")
assert result.returncode == 0, result.stderr
assert state["actions"] == [{"op":"restart","dest":NAME}], state["actions"]

print("PASS: TVGuard-only HTTP/2 create, backed-up migration, handshake rollback, ownership and idempotence")
