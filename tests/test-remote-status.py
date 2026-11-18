#!/usr/bin/env python3
"""执行状态最小化 shell，模拟 OpenWrt jsonfilter 解析；只允许固定 9 字段。"""
import json,subprocess,tempfile
from pathlib import Path

root=Path(__file__).resolve().parent.parent
source=(root/"root/usr/libexec/tvguard-remote-status").read_text()
with tempfile.TemporaryDirectory(prefix="tvguard-status-") as wd:
    p=Path(wd)
    status=p/"mock-status"
    jf=p/"mock-jsonfilter"
    sh=p/"status.sh"
    orig={"mode":"child","watch_seconds":0,"remaining_seconds":3600,"quota_seconds":3600,
          "bonus_seconds":0,"bonus_limit_seconds":7200,"bonus_undo_available":0,
          "enforce":1,"blocked":0,"agent_activity":"private","agent_package":"private",
          "pps":300,"agent_ui_structure_fingerprint":"private","traffic_class":"active"}
    def write(data):
        status.write_text("#!/bin/sh\ncat <<'EOF'\n"+json.dumps(data,ensure_ascii=False,separators=(',',':'))+"\nEOF\n")
        status.chmod(0o755)
    write(orig)
    jf.write_text("#!/usr/bin/env python3\nimport json,sys\ntry:\n a=sys.argv\n d=json.loads(a[a.index('-s')+1]); k=a[a.index('-e')+1].split('.',1)[1]\n v=d[k]\n assert type(v) in (str,int)\n print(v)\nexcept (ValueError,IndexError,KeyError,AssertionError): sys.exit(1)\n")
    jf.chmod(0o755)
    sh.write_text(source.replace("/usr/libexec/tvguard-status status",str(status)).
        replace("command -v jsonfilter >/dev/null 2>&1 || exit 1","[ -x '"+str(jf)+"' ] || exit 1").
        replace('jsonfilter -s',str(jf)+' -s'))
    sh.chmod(0o755)
    def run():
        return subprocess.run(["/bin/sh",str(sh)],capture_output=True,text=True,timeout=5)
    r=run()
    assert r.returncode==0,(r.stderr,r.stdout)
    out=json.loads(r.stdout)
    keys={"mode","watch_seconds","remaining_seconds","quota_seconds","bonus_seconds",
          "bonus_limit_seconds","bonus_undo_available","enforce","blocked"}
    assert set(out)==keys,out
    assert out["watch_seconds"]==0 and out["mode"]=="child"
    assert "private" not in r.stdout and "agent_" not in r.stdout and '"pps"' not in r.stdout
    write({**orig,"mode":"unknown"})
    assert run().returncode!=0,"invalid mode accepted"
    write({k:v for k,v in orig.items() if k!="enforce"})
    assert run().returncode!=0,"missing enforce accepted"
    write({**orig,"blocked":2})
    assert run().returncode!=0,"invalid boolean accepted"
print("PASS: 9-key remote status allowlist, zero-watch handling, fail-closed schema")
