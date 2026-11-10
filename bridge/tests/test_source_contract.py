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
pair = (p/'root/usr/libexec/tvguard-agent-bridge-pair').read_text()
assert 'pair-window' in pair and 'now + 120' in pair
assert 'TOKEN1|' in cgi and 'PAIR1' in cgi
assert 'REMOTE_ADDR' in cgi and 'pair-claim' in cgi
assert 'USED_S' not in pair and 'iptables' not in pair
report=(p/'root/usr/libexec/tvguard-agent-bridge-report').read_text()
soak=(p/'root/usr/libexec/tvguard-agent-bridge-soak').read_text()
assert 'player_state_unresolved_audio_hint_off' in report
assert 'player_open_audio_inactive' not in report
assert 'last_received_epoch' in report and 'report_seq=' in report
assert 'soak-v2.csv' in report and 'soak-v2.csv' in soak
assert 'repeated_report_not_new_evidence' in soak
assert 'agent_process_restart_suspected' in soak
assert 'current_seq' in soak and 'last_seq' in soak
assert 'agent_stale' in soak
assert 'is_new_report' in report
print('bridge isolation / freshness / BusyBox / one-tap pairing checks PASS')
