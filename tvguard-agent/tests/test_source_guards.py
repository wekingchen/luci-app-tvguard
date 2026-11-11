#!/usr/bin/env python3
"""Cheap source-level guardrails; device tests are still mandatory."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = root / "app/src/main"
manifest = (src / "AndroidManifest.xml").read_text()
assert "android.permission.PACKAGE_USAGE_STATS" in manifest
assert "android.permission.RECEIVE_BOOT_COMPLETED" in manifest
assert "android.permission.INTERNET" in manifest
assert 'android:usesCleartextTraffic="true"' in manifest
assert 'android:allowBackup="false"' in manifest
assert 'android:usesCleartextTraffic="true"' in manifest
service = (src / "java/com/tvguard/agent/MonitorService.java").read_text()
assert "SAMPLE_INTERVAL_MS = 5000L" in service
assert "MAX_EVENTS_PER_POLL = 4096" in service
assert "recentActivity.lastVideo()" in service
assert "recentActivity.lastNonLauncher()" in service
assert "recentActivity.lastEvents(6)" in service
history = (src / "java/com/tvguard/agent/VideoActivityHistory.java").read_text()
assert "CAPACITY = 24" in history
assert "new ArrayDeque<Event>(CAPACITY)" in history
assert "recent.removeFirst()" in history
assert "java.io." not in history
assert "SharedPreferences" not in history
assert "SQLite" not in history
assert "startForeground(NOTIFICATION_ID, notification)" in service
assert "stopForeground(true)" in service
main_activity = (src / "java/com/tvguard/agent/MainActivity.java").read_text()
assert "if (MonitorService.isEnabled(this))" in main_activity
assert "startService(new Intent(this, MonitorService.class))" in main_activity
assert '事件超限，前台待确认' in service
assert 'SamplingWindow.plan(now, lastScanEnd)' in service
assert 'before.sampledMs' in service
assert "GET_USAGE_STATS" in service
assert "MODE_ALLOWED" in service
assert "getBoolean(\"enabled\", false)" in service
assert "android.util.Log" not in service
assert "java.io." not in service
assert "SQLite" not in service
assert "BridgeClient.maybeSend" in service
assert "REPORT_INTERVAL_MS = 10000L" in service
assert 'new HandlerThread("tvguard-uplink"' in service
assert 'HeartbeatState.isFresh(now, sample.sampledMs)' in service
assert 'fresh ? sample.currentPackage : "unknown"' in service
assert service.index('BridgeClient.maybeSend(') < service.index('private void sampleOnce()')
assert "reportHandler.removeCallbacksAndMessages(null)" in service
bridge_client = (src / "java/com/tvguard/agent/BridgeClient.java").read_text()
assert "setUseCaches(false)" in bridge_client
assert "setInstanceFollowRedirects(false)" in bridge_client
assert "Proxy.NO_PROXY" in bridge_client
assert "android.util.Log" not in bridge_client
assert "java.io.File" not in bridge_client
assert "SharedPreferences.Editor" in service
assert "editor.commit()" in service
main_activity = (src / "java/com/tvguard/agent/MainActivity.java").read_text()
editor = (src / "java/com/tvguard/agent/TvAddressEditor.java").read_text()
assert "TVGuard 助手 · 0.2.5" in main_activity
watchdog = (src / "java/com/tvguard/agent/WatchdogReceiver.java").read_text()
assert "INTERVAL_MS = 30000L" in watchdog
assert "AlarmManager.ELAPSED_REALTIME" in watchdog
assert "ELAPSED_REALTIME_WAKEUP" not in watchdog
assert "context.startService(new Intent(context, MonitorService.class))" in watchdog
assert "WatchdogReceiver.schedule(this)" in service
assert "WatchdogReceiver.cancel(context)" in service
assert '<receiver android:name=".WatchdogReceiver" android:exported="false" />' in manifest
assert '<service' in manifest and 'RecoveryJobService' in manifest
assert 'android.permission.BIND_JOB_SERVICE' in manifest
assert 'android:exported="true"' in manifest
recovery_scheduler = (src / "java/com/tvguard/agent/RecoveryScheduler.java").read_text()
recovery_job = (src / "java/com/tvguard/agent/RecoveryJobService.java").read_text()
boot_receiver = (src / "java/com/tvguard/agent/BootReceiver.java").read_text()
assert "JOB_ID = 7025" in recovery_scheduler
assert "PERIOD_MS = 15L * 60L * 1000L" in recovery_scheduler
assert ".setPersisted(true)" in recovery_scheduler
assert ".setPeriodic(PERIOD_MS)" in recovery_scheduler
assert "RecoveryScheduler.ensureScheduled(context)" in service
assert "RecoveryScheduler.cancel(context)" in service
assert "RecoveryScheduler.ensureScheduled(this)" in service
assert "RecoveryScheduler.ensureScheduled(context)" in boot_receiver
assert "Intent.ACTION_MY_PACKAGE_REPLACED" in boot_receiver
assert "RecoveryJobService" in recovery_job
assert "startService(new Intent(this, MonitorService.class))" in recovery_job
assert "192.168.101.99" in bridge_client
assert "PAIR1" in bridge_client
assert "TOKEN1|" in bridge_client
assert "TvAddressEditor.show" in main_activity
assert "autoPair(MainActivity.this" in main_activity
assert "EditText" not in main_activity
assert "GridLayout" in editor and "清空" in editor
print("Agent source guardrails: PASS")
