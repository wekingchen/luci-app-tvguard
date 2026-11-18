#!/usr/bin/env python3
"""通过真实 /bin/sh 执行管理员签发、统计、撤销及重新签发，不修改 N1。"""
import hashlib
import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = (root/"root/usr/libexec/tvguard-remote-admin").read_text()
random_file=(root/"root/usr/libexec/tvguard-random-hex").resolve()
with tempfile.TemporaryDirectory(prefix="tvguard-admin-e2e-") as temp:
    base=Path(temp)
    persistent=base/"persistent"
    pending=base/"pending"
    admin=base/"admin.sh"
    persistent.mkdir()
    pending.mkdir()
    script=source.replace("ROOT=/mnt/mmcblk2p4/tvguard-remote",f"ROOT={persistent}").replace(
        "PAIR_DIR=/tmp/tvguard-remote",f"PAIR_DIR={pending}").replace(
        "/usr/libexec/tvguard-random-hex",str(random_file))
    # 管理员测试同样保留真实 require_storage，只把挂载表映射为隔离夹具。
    fake_mounts=base/"mounts"
    fake_mounts.write_text("device /mnt/mmcblk2p4 xfs rw,relatime 0 0\n")
    script=script.replace("/proc/mounts",str(fake_mounts))
    admin.write_text(script)
    admin.chmod(0o700)

    def run(action):
        return subprocess.run(["/bin/sh",str(admin),action],capture_output=True,text=True,timeout=8)

    out=run("pair")
    assert out.returncode==0,(out.stderr,out.stdout)
    code=out.stdout.strip().rsplit("：",1)[-1]
    assert re.fullmatch(r"[0-9a-f]{32}",code),out.stdout
    pairfile=pending/"pair"
    digest,expiry,generation=pairfile.read_text().strip().split("|")
    assert digest==hashlib.sha256(code.encode()).hexdigest()
    assert int(expiry)>int(time.time())
    assert re.fullmatch(r"[0-9a-f]{64}",generation)
    assert (persistent/"generation").read_text().strip()==generation

    # 手机端会话记录只存摘要与 generation，不存明文 token。
    session=persistent/"sessions"
    session.write_text(hashlib.sha256(b"old-session").hexdigest()+"|"+
                       str(int(time.time())+1200)+"|"+generation+"\n")
    state=json.loads(run("status").stdout)
    assert state["paired"]==1,state
    assert len(state["devices"])==1 and state["devices"][0]["expires"]>int(time.time()),state
    assert state["devices"][0]["id"]==hashlib.sha256(b"old-session").hexdigest()[:16]

    # 老版仍有效会话升级迁移为 0=永不过期，并可单独撤销。
    mig=run("migrate")
    assert mig.returncode==0,(mig.stdout,mig.stderr)
    assert session.read_text().split("|")[1]=="0"
    state=json.loads(run("status").stdout)
    assert state["paired"]==1 and state["devices"][0]["expires"]==0
    invalid=run("revoke-device not-a-valid-id")
    assert invalid.returncode!=0
    target=state["devices"][0]["id"]
    one=run("revoke-device "+target)
    assert one.returncode==0,(one.stdout,one.stderr)
    assert json.loads(run("status").stdout)["paired"]==0
    marker=persistent/"revoked"/hashlib.sha256(b"old-session").hexdigest()
    assert marker.exists(), "selective revoke marker missing"
    # 旧会话即使被并发 CGI 写回，仍不能绕过单台撤销。
    session.write_text(hashlib.sha256(b"old-session").hexdigest()+"|0|"+generation+"|0|Browser\n")
    assert json.loads(run("status").stdout)["paired"]==0
    session.write_text(hashlib.sha256(b"still-authorized").hexdigest()+"|0|"+generation+"|0|Browser\n")

    # 撤销必须先旋转 generation，过期旧会话即使被并发写回也不得计入。
    revoked=run("revoke-all")
    assert revoked.returncode==0,revoked.stderr
    new_generation=(persistent/"generation").read_text().strip()
    assert new_generation!=generation and re.fullmatch(r"[0-9a-f]{64}",new_generation)
    assert not pairfile.exists() and not session.exists()
    assert not (persistent/"revoked").exists(), "revoke-all should clear stale per-device markers"
    session.write_text(hashlib.sha256(b"resurrected-session").hexdigest()+"|"+
                       str(int(time.time())+1200)+"|"+generation+"\n")
    assert json.loads(run("status").stdout)["paired"]==0

    # 再次签发时沿用新的 generation，配对码与旧码不同。
    second=run("pair")
    assert second.returncode==0,second.stderr
    next_code=second.stdout.strip().rsplit("：",1)[-1]
    assert next_code!=code
    assert pairfile.read_text().strip().split("|")[2]==new_generation
print("PASS: administrator real-shell pair, revoke generation, status, and re-pair")
