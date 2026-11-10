from pathlib import Path
p=Path(__file__).resolve().parents[1]
cgi=(p/'root/www/cgi-bin/tvguard-agent').read_text()
report=(p/'root/usr/libexec/tvguard-agent-bridge-report').read_text()
ipk=(p/'../scripts/build-agent-bridge-ipk.sh').resolve().read_text()
assert '/var/run/tvguard-agent-bridge' in cgi
assert 'tvguard.main.ip' in cgi
assert 'CONTENT_LENGTH' in cgi
assert 'REQUEST_METHOD' in cgi and 'REMOTE_ADDR' in cgi
assert 'agent-bridge.key' in cgi
assert '>>' not in cgi  # no ever-growing history
assert 'USED_S' not in cgi and 'iptables' not in cgi
assert 'billing_effect=none' in report
assert 'luci-app-tvguard' not in ipk
print('bridge isolation / no-persistent-log checks PASS')
