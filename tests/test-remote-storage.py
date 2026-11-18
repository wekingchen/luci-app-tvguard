#!/usr/bin/env python3
"""运行源码中的原始 storage_ok/require_storage，不允许替换函数本体。"""
import os
import re
import shlex
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
cgi = (root/"root/usr/share/tvguard-remote/www/cgi-bin/tvg").read_text()
admin = (root/"root/usr/libexec/tvguard-remote-admin").read_text()

def extract(script, name):
    found = re.search(r"(?ms)^"+re.escape(name)+r"\(\) \{\n.*?^\}",script)
    assert found, name + " not found"
    result = found.group(0)
    assert 'index("," $4 ",", ",rw,")' in result, result
    return result

busybox = shutil.which("busybox")
assert busybox, "Install busybox in CI; cannot skip BusyBox compatibility tests"

with tempfile.TemporaryDirectory(prefix="tvg-storage-test-") as temp:
    base=Path(temp)
    mounts=base/"mounts"
    data=base/"remote"
    data.mkdir()
    generation=data/"generation"
    generation.write_text("ab"*32+"\n")
    sessions=data/"sessions"
    bb_dir=base/"busybox-bin"
    bb_dir.mkdir()
    (bb_dir/"awk").symlink_to(busybox)
    for executable, prefix in [("system-awk", ""), ("BusyBox-awk", str(bb_dir)+os.pathsep)]:
        env=os.environ.copy()
        env["PATH"]=prefix+env.get("PATH","")
        for name,body in [("cgi-storage",extract(cgi,"storage_ok")),
                          ("admin-storage",extract(admin,"require_storage"))]:
            # 用临时挂载表替换 /proc/mounts，但保留生产函数的其它全部逻辑。
            body=body.replace("/proc/mounts",shlex.quote(str(mounts)))
            script="\n".join([
                "ROOT="+shlex.quote(str(data)),
                "SESSIONS="+shlex.quote(str(sessions)),
                "GENERATION="+shlex.quote(str(generation)),
                body,
                ("storage_ok" if name=="cgi-storage" else "require_storage"),
            ])
            def evaluate(options,expected):
                mounts.write_text("device /mnt/mmcblk2p4 xfs "+options+" 0 0\n")
                ret=subprocess.run(["/bin/sh","-c",script],env=env,
                                   capture_output=True,text=True,timeout=5)
                assert (ret.returncode==0)==expected,(executable,name,options,
                    ret.returncode,ret.stderr)
            evaluate("rw,relatime",True)
            evaluate("ro,relatime",False)
            evaluate("xrw,relatime",False)
            evaluate("rwish,relatime",False)
            mounts.write_text("device /mnt/mmcblk2p4 ext4 rw,relatime 0 0\n")
            bad_fs=subprocess.run(["/bin/sh","-c",script],env=env,capture_output=True,text=True)
            assert bad_fs.returncode!=0,(executable,name,"invalid filesystem")
            if name=="cgi-storage":
                mounts.write_text("device /mnt/mmcblk2p4 xfs rw,relatime 0 0\n")
                generation.unlink()
                missing=subprocess.run(["/bin/sh","-c",script],env=env,capture_output=True,text=True)
                assert missing.returncode!=0,(executable,name,"missing generation")
                generation.symlink_to(data/"untrusted")
                symlink=subprocess.run(["/bin/sh","-c",script],env=env,capture_output=True,text=True)
                assert symlink.returncode!=0,(executable,name,"symlinked generation")
                generation.unlink()
                generation.write_text("ab"*32+"\n")
print("PASS: production storage functions, positive/negative XFS mount tests with mawk and BusyBox awk")
