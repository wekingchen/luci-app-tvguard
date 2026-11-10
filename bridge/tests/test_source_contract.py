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
postinst=(p/'ipkg/postinst').read_text()
assert 'od -An' not in postinst
assert 'sha256sum' in postinst
assert 'bs=32 count=1' in postinst
assert 'control/conffiles' in ipk
assert 'printf \'/etc/tvguard/agent-bridge.key' not in ipk
print('bridge isolation / BusyBox key generation / opkg conffiles checks PASS')
