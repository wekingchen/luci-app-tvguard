import os
import subprocess
import tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=(root/'root/www/cgi-bin/tvguard-agent').read_text()
with tempfile.TemporaryDirectory() as folder:
    d=Path(folder)
    key=d/'token'
    key.write_text('0123456789abcdef0123456789abcdef\n')
    state=d/'ram'
    uci=d/'uci'
    uci.write_text('#!/bin/sh\nprintf "192.168.101.76\\n"\n')
    uci.chmod(0o755)
    script=(source.replace('/etc/tvguard/agent-bridge.key',str(key))
                 .replace('/var/run/tvguard-agent-bridge',str(state))
                 .replace('uci -q get tvguard.main.ip',str(uci)+' -q get tvguard.main.ip'))
    target=d/'bridge'
    target.write_text(script)
    target.chmod(0o755)
    base='TVG1|0123456789abcdef0123456789abcdef|1|com.gitvdemo.video|com.gala.video.app.player.PlayerActivity|1|1|1794319200000\n'
    def send(body=base,remote='192.168.101.76',method='POST'):
        env={**os.environ,'REQUEST_METHOD':method,'REMOTE_ADDR':remote,
             'CONTENT_LENGTH':str(len(body))}
        p=subprocess.run(['dash',str(target)],input=body,text=True,
                         capture_output=True,env=env,timeout=5)
        return p.stdout
    assert '200 OK' in send()
    assert (state/'latest').exists()
    assert 'com.gitvdemo.video' in (state/'latest').read_text()
    assert '403 Forbidden' in send(remote='192.168.101.75')
    assert '403 Forbidden' in send(body=base.replace('0123456789abcdef','0000000000000000'))
    assert '405 Method Not Allowed' in send(method='GET')
    assert '400 Bad Request' in send(body=base.replace('com.gitvdemo.video','bad;touch'))
    assert '400 Bad Request' in send(body=base.replace('|1|1|179431','|9|1|179431'))
    assert '400 Bad Request' in send(body='X'*513)
    assert len(list(state.glob('latest*')))==1
print('bridge HTTP validation, authorization and RAM-only write PASS')
