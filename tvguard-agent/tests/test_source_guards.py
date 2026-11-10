#!/usr/bin/env python3
"""Cheap source-level guardrails; device tests are still mandatory."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = root / "app/src/main"
manifest = (src / "AndroidManifest.xml").read_text()
assert "android.permission.PACKAGE_USAGE_STATS" in manifest
assert "android.permission.RECEIVE_BOOT_COMPLETED" in manifest
assert "android.permission.INTERNET" not in manifest
assert 'android:allowBackup="false"' in manifest
assert 'android:usesCleartextTraffic="false"' in manifest
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
assert "INTERNET" not in service
assert "SharedPreferences.Editor" in service
assert "editor.commit()" in service
print("Agent source guardrails: PASS")
