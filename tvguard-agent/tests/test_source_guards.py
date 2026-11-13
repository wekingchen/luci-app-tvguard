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
assert "recentActivity.lastNonLauncher()" in service
assert "VideoActivityHistory" not in service
assert not (src / "java/com/tvguard/agent/VideoActivityHistory.java").exists()
assert "recentActivity.lastEvents(6)" in service
history = (src / "java/com/tvguard/agent/ForegroundActivityHistory.java").read_text()
assert "CAPACITY = 24" in history
assert "new ArrayDeque<Event>(CAPACITY)" in history
assert "recent.removeFirst()" in history
assert "java.io." not in history
assert "SharedPreferences" not in history
assert "SQLite" not in history
for forbidden in ("com.gitvdemo.video", "com.ktcp.video", "com.hunantv.license",
                  "org.smarttube.stable", "com.youku.tv", "com.iqiyi.tv",
                  "com.bilibili.tv"):
    assert forbidden not in history
assert "isVideoPackage" not in history
assert "startForeground(" not in service
assert "stopForeground(" not in service
assert "static boolean isRunning()" in service
gradle = (root / "app/build.gradle").read_text()
assert "versionCode 16" in gradle
assert "versionName '0.3.3'" in gradle

main_activity = (src / "java/com/tvguard/agent/MainActivity.java").read_text()
assert "不维护视频 App 白名单" in main_activity
assert "isVideoPackage" not in main_activity
assert "if (MonitorService.isEnabled(this))" in main_activity
assert "startService(new Intent(this, MonitorService.class))" in main_activity
assert '"event_overflow"' in service
assert '"package_only_after_overflow"' in service
assert 'SamplingWindow.plan(now, lastScanEnd)' in service
assert 'Snapshot.diagnostic(' in service
assert 'usageAccessState(MonitorService.this)' in service
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
assert "fallbackPackage(UsageStatsManager manager" in service
assert '"usage_stats"' in service
assert '"usage_events"' in service
assert '"permission_unconfirmed"' in service
assert "sample.currentPackage.length() != 0" in service
assert "sample.currentClass.length() != 0" in service
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
assert "TVGuard 助手 · 0.3.3" in main_activity
gradle = (root / "app/build.gradle").read_text()
assert "targetSdk 23" in gradle
assert "disable 'ExpiredTargetSdkVersion'" in gradle
assert not (src / "java/com/tvguard/agent/WatchdogReceiver.java").exists()
assert "AlarmManager" not in service
assert "WatchdogReceiver" not in service
assert "WatchdogReceiver" not in manifest
assert '<service' in manifest and 'RecoveryJobService' in manifest
assert 'android.permission.BIND_JOB_SERVICE' in manifest
assert 'android:exported="true"' in manifest
recovery_scheduler = (src / "java/com/tvguard/agent/RecoveryScheduler.java").read_text()
recovery_job = (src / "java/com/tvguard/agent/RecoveryJobService.java").read_text()
boot_receiver = (src / "java/com/tvguard/agent/BootReceiver.java").read_text()
assert "PERSISTED_JOB_ID = 7025" in recovery_scheduler
assert "FAST_JOB_ID_A = 7026" in recovery_scheduler
assert "FAST_JOB_ID_B = 7027" in recovery_scheduler
assert "PERSISTED_PERIOD_MS = 15L * 60L * 1000L" in recovery_scheduler
assert "FAST_MIN_LATENCY_MS = 20000L" in recovery_scheduler
assert "FAST_DEADLINE_MS = 30000L" in recovery_scheduler
assert ".setPersisted(true)" in recovery_scheduler
assert ".setPeriodic(PERSISTED_PERIOD_MS)" in recovery_scheduler
assert ".setPersisted(false)" in recovery_scheduler
assert ".setMinimumLatency(FAST_MIN_LATENCY_MS)" in recovery_scheduler
assert ".setOverrideDeadline(FAST_DEADLINE_MS)" in recovery_scheduler
assert "scheduleNextFast" in recovery_scheduler
assert "ensureFastScheduled" in recovery_scheduler
assert "RecoveryScheduler.ensureScheduled(context)" in service
assert "RecoveryScheduler.cancel(context)" in service
assert "RecoveryScheduler.ensureScheduled(this)" in service
assert "RecoveryScheduler.ensureScheduled(context)" in boot_receiver
assert "Intent.ACTION_MY_PACKAGE_REPLACED" in boot_receiver
assert "WatchdogReceiver" not in boot_receiver
assert "RecoveryScheduler.scheduleNextFast(this, params.getJobId())" in recovery_job
assert "RecoveryScheduler.ensureFastScheduled(this)" in recovery_job
assert "if (!MonitorService.isRunning())" in recovery_job
assert "startService(new Intent(this, MonitorService.class))" in recovery_job
assert "192.168.101.99" in bridge_client
assert "PAIR1" in bridge_client
assert "TOKEN1|" in bridge_client
protocol = (src / "java/com/tvguard/agent/BridgeProtocol.java").read_text()
assert '"TVG2|"' in protocol
assert '"TVG3|"' in protocol
assert '"TVG4|"' in protocol
assert "activityTrail" in protocol
assert "bodyV3" in protocol
assert "bodyV4" in protocol
assert "usageAccess" in protocol and "foregroundSource" in protocol
assert "foregroundStatus" in protocol
ui_service = (src / "java/com/tvguard/agent/UiStructureAccessibilityService.java").read_text()
ui_config = (src / "res/xml/tvguard_accessibility_service.xml").read_text()
assert "UiStructureAccessibilityService" in manifest
assert "android.permission.BIND_ACCESSIBILITY_SERVICE" in manifest
assert "canRetrieveWindowContent" in ui_config
assert "flagReportViewIds" in ui_config
assert "MAX_NODES = 96" in ui_service
assert "MAX_DEPTH = 10" in ui_service\nassert "REFRESH_INTERVAL_MS = 5000L" in ui_service\nassert "refreshHandler.postDelayed(refreshTask, REFRESH_INTERVAL_MS)" in ui_service\nassert "refreshHandler.removeCallbacks(refreshTask)" in ui_service
assert "getViewIdResourceName" in ui_service
assert "getText(" not in ui_service
assert "getContentDescription(" not in ui_service
assert "SharedPreferences" not in ui_service
assert "SQLite" not in ui_service
assert "java.io.File" not in ui_service
assert "android.util.Log" not in ui_service
assert "UiStructureAccessibilityService.snapshot()" in service
assert "uiFingerprint" in bridge_client
assert "Settings.ACTION_ACCESSIBILITY_SETTINGS" in main_activity
assert "resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)" in main_activity
assert "ActivityNotFoundException" in main_activity
assert "系统未提供无障碍设置入口" in main_activity
assert "TvAddressEditor.show" in main_activity
assert "autoPair(MainActivity.this" in main_activity
assert "EditText" not in main_activity
assert "GridLayout" in editor and "清空" in editor
print("Agent source guardrails: PASS")
