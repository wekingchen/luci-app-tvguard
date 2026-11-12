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
    legacy='TVG1|0123456789abcdef0123456789abcdef|1|com.gitvdemo.video|com.gala.video.app.player.PlayerActivity|1|1|1794319200000\n'
    base='TVG2|0123456789abcdef0123456789abcdef|2|com.gitvdemo.video|com.gala.video.app.player.PlayerActivity|1|1|1794319200000|allowed|usage_events|full_context\n'
    trail='com.gala.video.plugincenter.component.InstrActivityProxy0~com.gala.video.app.player.PlayerActivity'
    v3='TVG3|0123456789abcdef0123456789abcdef|3|com.gitvdemo.video|com.gala.video.plugincenter.component.InstrActivityProxy0|1|1|1794319210000|allowed|usage_events|full_context|'+trail+'\n'
    def send(body=base,remote='192.168.101.76',method='POST'):
        env={**os.environ,'REQUEST_METHOD':method,'REMOTE_ADDR':remote,
             'CONTENT_LENGTH':str(len(body))}
        p=subprocess.run(['dash',str(target)],input=body,text=True,
                         capture_output=True,env=env,timeout=5)
        return p.stdout
    assert '200 OK' in send()
    assert (state/'latest').exists()
    latest=(state/'latest').read_text()
    assert 'com.gitvdemo.video' in latest
    assert latest.rstrip().endswith('|allowed|usage_events|full_context|none')
    assert '200 OK' in send(body=v3)
    assert (state/'latest').read_text().rstrip().endswith('|allowed|usage_events|full_context|'+trail)
    assert '200 OK' in send(body=legacy)
    assert (state/'latest').read_text().rstrip().endswith('|legacy|legacy|legacy|none')
    assert '403 Forbidden' in send(remote='192.168.101.75')
    assert '403 Forbidden' in send(body=base.replace('0123456789abcdef','0000000000000000'))
    assert '405 Method Not Allowed' in send(method='GET')
    assert '400 Bad Request' in send(body=base.replace('com.gitvdemo.video','bad;touch'))
    assert '400 Bad Request' in send(body=base.replace('|1|1|179431','|9|1|179431'))
    assert '400 Bad Request' in send(body=base.replace('|allowed|usage_events|full_context','|allowed|bad-source!|full_context'))
    assert '400 Bad Request' in send(body=v3.replace(trail, trail+';bad'))
    assert '400 Bad Request' in send(body='X'*769)
    assert len(list(state.glob('latest*')))==1
print('bridge TVG1/TVG2/TVG3 validation, bounded trail diagnostics, authorization and RAM-only write PASS')
