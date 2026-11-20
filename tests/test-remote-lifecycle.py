#!/usr/bin/env python3
"""用模拟 init/procd/curl 实际执行管理员服务启停，检验监听失败的回滚。"""
import os, subprocess, re, tempfile
from pathlib import Path

repo=Path(__file__).resolve().parent.parent
source=(repo/"root/usr/libexec/tvguard-remote-admin").read_text()
with tempfile.TemporaryDirectory(prefix="tvguard-lifecycle-") as temp:
    p=Path(temp)
    data=p/"root"
    data.mkdir()
    etc=p/"etc"
    etc.mkdir()
    enabled=etc/"remote-enabled"
    lan_enabled=etc/"remote-lan-enabled"
    mock_init=p/"mock-init"
    mock_curl=p/"mock-curl"
    mock_lan=p/"mock-lan"
    lan_code=p/"lan-code"
    lan_ip=p/"lan-ip"
    service_log=p/"service.log"
    mock_init.write_text("#!/bin/sh\nprintf '%s\\n' \"$1\" >> '"+str(service_log)+"'\nexit 0\n")
    mock_curl.write_text(
        "#!/bin/sh\n"
        "case \"$*\" in\n"
        "  *127.0.0.1:18765*) cat '"+str(p/"code")+"' ;;\n"
        "  *192.168.101.99:18765*) cat '"+str(lan_code)+"' ;;\n"
        "  *) printf 000 ;;\n"
        "esac\n"
    )
    mock_lan.write_text("#!/bin/sh\n[ -s '"+str(lan_ip)+"' ] || exit 1\ncat '"+str(lan_ip)+"'\n")
    mock_lan.chmod(0o700)
    lan_ip.write_text("192.168.101.99\n")
    lan_code.write_text("200\n")
    mock_init.chmod(0o700)
    mock_curl.chmod(0o700)
    script=source.replace("ROOT=/mnt/mmcblk2p4/tvguard-remote","ROOT="+str(data))
    script=script.replace("ENABLED=/etc/tvguard/remote-enabled","ENABLED="+str(enabled))
    script=script.replace("LAN_ENABLED=/etc/tvguard/remote-lan-enabled","LAN_ENABLED="+str(lan_enabled))
    script=script.replace("INIT=/etc/init.d/tvguard-remote","INIT="+str(mock_init))
    script=script.replace("LAN_HELPER=/usr/libexec/tvguard-remote-lan-ip","LAN_HELPER="+str(mock_lan))
    script=script.replace("curl --noproxy","'"+str(mock_curl)+"' --noproxy")
    script=script.replace("command -v uhttpd >/dev/null 2>&1","true")
    script=script.replace("mkdir -p /etc/tvguard; chmod 700 /etc/tvguard","mkdir -p '"+str(etc)+"'; chmod 700 '"+str(etc)+"'")
    script=script.replace("mkdir -p /etc/tvguard\n    chmod 700 /etc/tvguard","mkdir -p '"+str(etc)+"'\n    chmod 700 '"+str(etc)+"'")
    script=re.sub(r"(?ms)^require_storage\(\) \{\n.*?^\}",'require_storage() { :; }',script,count=1)
    sh=p/"admin.sh"
    sh.write_text(script)
    sh.chmod(0o700)
    def run(action):
        return subprocess.run(["/bin/sh",str(sh),action],text=True,capture_output=True,timeout=9)
    (p/"code").write_text("401")
    first=run("enable")
    assert first.returncode==0,(first.stdout,first.stderr)
    assert enabled.read_text().strip()=="1"
    assert "restart" in service_log.read_text()
    state=run("status")
    assert state.returncode==0
    assert '"listener":true' in state.stdout,state.stdout
    assert '"lan_listener":false' in state.stdout,state.stdout
    lan_enabled.write_text("1\n")
    lan_ready=run("status")
    assert '"lan_listener":true' in lan_ready.stdout,lan_ready.stdout
    lan_code.write_text("000\n")
    lan_down=run("status")
    assert '"lan_listener":false' in lan_down.stdout,lan_down.stdout
    lan_ip.write_text("")
    lan_without_ip=run("status")
    assert '"lan_listener":false' in lan_without_ip.stdout,lan_without_ip.stdout
    lan_enabled.write_text("0\n")

    (p/"code").write_text("200")
    wrong=run("enable")
    assert wrong.returncode!=0,(wrong.stdout,wrong.stderr)
    assert enabled.read_text().strip()=="0",enabled.read_text()
    assert service_log.read_text().splitlines()[-2:]==["stop","disable"],service_log.read_text()
    stop=run("disable")
    assert stop.returncode==0,(stop.stdout,stop.stderr)
    assert enabled.read_text().strip()=="0"
print("PASS: parent service readiness requires anonymous 401; failed startup disables and stops service")
