package com.tvguard.agent;

import android.app.AppOpsManager;
import android.media.AudioManager;
import android.os.PowerManager;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;
import java.util.List;

/**
 * Volatile, bounded observer. No file I/O, database, log, network or event queue.
 * UsageEvents are sampled for short time windows only. States are hints, never billing.
 */
public final class MonitorService extends Service {
    private static final long SAMPLE_INTERVAL_MS = 5000L;
    private static final long REPORT_INTERVAL_MS = 10000L;
    private static final int MAX_EVENTS_PER_POLL = 4096;
    private static volatile Snapshot latest = Snapshot.empty("未启动");
    private static volatile boolean running;
    private HandlerThread worker;
    private Handler handler;
    private HandlerThread reportWorker;
    private Handler reportHandler;
    private long lastScanEnd;
    private final ForegroundActivityHistory recentActivity = new ForegroundActivityHistory();

    public static final class Snapshot {
        public final String state;
        public final String currentPackage;
        public final String currentClass;
        public final String lastOtherPackage;
        public final String lastOtherClass;
        public final long changedMs;
        public final long sampledMs;
        public final ForegroundActivityHistory.Event recentNonLauncher;
        public final ForegroundActivityHistory.Event[] timeline;
        public final String usageAccess;
        public final String foregroundSource;
        public final String foregroundStatus;

        Snapshot(String state, String currentPackage, String currentClass,
                 String lastOtherPackage, String lastOtherClass,
                 long changedMs, long sampledMs,
                 ForegroundActivityHistory.Event recentNonLauncher,
                 ForegroundActivityHistory.Event[] timeline,
                 String usageAccess, String foregroundSource, String foregroundStatus) {
            this.state = state;
            this.currentPackage = currentPackage;
            this.currentClass = currentClass;
            this.lastOtherPackage = lastOtherPackage;
            this.lastOtherClass = lastOtherClass;
            this.changedMs = changedMs;
            this.sampledMs = sampledMs;
            this.recentNonLauncher = recentNonLauncher;
            this.timeline = timeline.clone();
            this.usageAccess = usageAccess;
            this.foregroundSource = foregroundSource;
            this.foregroundStatus = foregroundStatus;
        }

        static Snapshot empty(String state) {
            return new Snapshot(state, "", "", "", "", 0L, 0L, null,
                    new ForegroundActivityHistory.Event[0],
                    "unknown", "none", "no_sample");
        }

        static Snapshot diagnostic(String state, long sampledMs,
                                   String usageAccess, String foregroundStatus) {
            return new Snapshot(state, "", "", "", "", 0L, sampledMs, null,
                    new ForegroundActivityHistory.Event[0],
                    usageAccess, "none", foregroundStatus);
        }
    }

    public static Snapshot snapshot() {
        return latest;
    }

    static boolean isRunning() {
        return running;
    }

    public static boolean isEnabled(Context context) {
        return context.getSharedPreferences("control", Context.MODE_PRIVATE)
                .getBoolean("enabled", false);
    }

    public static boolean setEnabled(Context context, boolean enabled) {
        SharedPreferences.Editor editor =
                context.getSharedPreferences("control", Context.MODE_PRIVATE)
                        .edit().putBoolean("enabled", enabled);
        boolean saved = editor.commit(); // One tiny write only on explicit user action.
        if (saved) {
            if (enabled) {
                RecoveryScheduler.ensureScheduled(context);
            } else {
                RecoveryScheduler.cancel(context);
            }
        }
        return saved;
    }

    static String usageAccessState(Context context) {
        AppOpsManager appOps =
                (AppOpsManager) context.getSystemService(Context.APP_OPS_SERVICE);
        if (appOps == null) return "unknown";
        int mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(), context.getPackageName());
        if (mode == AppOpsManager.MODE_ALLOWED) return "allowed";
        if (mode == AppOpsManager.MODE_DEFAULT) return "default";
        return "denied";
    }

    public static boolean hasUsageAccess(Context context) {
        return "allowed".equals(usageAccessState(context));
    }

    @Override
    public void onCreate() {
        super.onCreate();
        running = true;
        worker = new HandlerThread("tvguard-observe", Process.THREAD_PRIORITY_BACKGROUND);
        worker.start();
        handler = new Handler(worker.getLooper());
        handler.post(poll);
        // Keep uplink independent of UsageStats/AudioManager reads. A stalled
        // vendor UsageStats service must not silently stop N1 liveness reports.
        reportWorker = new HandlerThread("tvguard-uplink",
                Process.THREAD_PRIORITY_BACKGROUND);
        reportWorker.start();
        reportHandler = new Handler(reportWorker.getLooper());
        reportHandler.postDelayed(report, 2000L);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!isEnabled(this)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        // MiTV Android 6 explicitly rejects promotion of this third-party
        // service to foreground. Recovery is therefore owned by JobScheduler,
        // not by repeated foreground-service promotion attempts.
        RecoveryScheduler.ensureScheduled(this);
        return START_STICKY;
    }

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            if (!isEnabled(MonitorService.this)) {
                stopSelf();
                return;
            }
            try {
                sampleOnce();
            } catch (RuntimeException failure) {
                Snapshot before = latest;
                // Never mark a failed query as a successful new sample.
                latest = Snapshot.diagnostic(
                        "读取失败：" + failure.getClass().getSimpleName(),
                        System.currentTimeMillis(), usageAccessState(MonitorService.this),
                        "query_error_" + failure.getClass().getSimpleName());
                recentActivity.clear();
                lastScanEnd = 0L;
            }
            if (handler != null) {
                handler.postDelayed(this, SAMPLE_INTERVAL_MS);
            }
        }
    };

    // Independent latest-only LAN heartbeat: no disk log, queue or history.
    // Foreground diagnostics are sent even when exact Activity context is unavailable.
    private final Runnable report = new Runnable() {
        @Override
        public void run() {
            if (!isEnabled(MonitorService.this)) return;
            try {
                AccessibilityRecovery.reconcile(MonitorService.this);
                Snapshot sample = latest;
                long now = System.currentTimeMillis();
                boolean fresh = HeartbeatState.isFresh(now, sample.sampledMs);
                String pkg = fresh && sample.currentPackage.length() != 0
                        ? sample.currentPackage : "unknown";
                String cls = fresh && sample.currentClass.length() != 0
                        ? sample.currentClass : "unknown";
                String source = fresh ? sample.foregroundSource : "none";
                String status = fresh ? sample.foregroundStatus : "sample_stale";
                AudioManager audio = (AudioManager)
                        getSystemService(Context.AUDIO_SERVICE);
                PowerManager power = (PowerManager)
                        getSystemService(Context.POWER_SERVICE);
                boolean activeAudio = audio != null && audio.isMusicActive();
                boolean screenOn = power != null && power.isInteractive();
                String activityTrail = fresh
                        ? BridgeProtocol.activityTrail(sample.timeline, pkg) : "none";
                UiStructureAccessibilityService.Snapshot ui =
                        UiStructureAccessibilityService.snapshot();
                long uiAgeMs = ui.sampledMs == 0L ? 0L :
                        Math.max(0L, now - ui.sampledMs);
                BridgeClient.maybeSend(MonitorService.this, pkg, cls,
                        activeAudio, screenOn, now, sample.usageAccess, source, status,
                        activityTrail, ui.packageName, uiAgeMs, ui.nodeCount,
                        ui.clickableCount, ui.focusedCount, ui.viewIdCount,
                        ui.fingerprint);
            } catch (RuntimeException e) {
                BridgeClient.markUplinkError("本地上报异常：" +
                        e.getClass().getSimpleName());
            } finally {
                if (reportHandler != null) {
                    reportHandler.postDelayed(this, REPORT_INTERVAL_MS);
                }
            }
        }
    };

    private String fallbackPackage(UsageStatsManager manager, long now) {
        List<UsageStats> stats;
        try {
            long from = Math.max(0L, now - 6L * 60L * 60L * 1000L);
            stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, from, now + 1000L);
        } catch (RuntimeException ignored) {
            return "";
        }
        if (stats == null) return "";
        String best = "";
        long bestTime = 0L;
        long cutoff = Math.max(0L, now - 6L * 60L * 60L * 1000L);
        for (UsageStats item : stats) {
            if (item == null) continue;
            String pkg = item.getPackageName();
            long used = item.getLastTimeUsed();
            if (pkg == null || pkg.length() == 0 || pkg.equals(getPackageName())
                    || used < cutoff || used > now + 5000L || used <= bestTime) {
                continue;
            }
            best = pkg;
            bestTime = used;
        }
        return best;
    }

    private void sampleOnce() {
        long now = System.currentTimeMillis();
        String access = usageAccessState(this);
        UsageStatsManager manager =
                (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        if (manager == null) {
            latest = Snapshot.diagnostic("系统未提供 UsageStats 服务", now,
                    access, "service_missing");
            recentActivity.clear();
            lastScanEnd = 0L;
            return;
        }

        SamplingWindow window = SamplingWindow.plan(now, lastScanEnd);
        if (window.reset) {
            recentActivity.clear();
        }
        Snapshot previous = latest;
        boolean reuseEventContext = !window.reset
                && "usage_events".equals(previous.foregroundSource);
        ForegroundReducer reducer = new ForegroundReducer(
                reuseEventContext ? previous.currentPackage : "",
                reuseEventContext ? previous.currentClass : "",
                reuseEventContext ? previous.lastOtherPackage : "",
                reuseEventContext ? previous.lastOtherClass : "",
                reuseEventContext ? previous.changedMs : 0L);

        UsageEvents events = null;
        try {
            events = manager.queryEvents(window.fromMs, now + 1000L);
        } catch (RuntimeException ignored) {
            // Vendor Android 6 builds may reject UsageEvents while still
            // returning package-level UsageStats. Fall through to that safer,
            // lower-confidence source instead of pretending the Agent is offline.
        }

        int processed = 0;
        boolean overflow = false;
        if (events != null) {
            UsageEvents.Event e = new UsageEvents.Event();
            while (events.hasNextEvent()) {
                if (processed++ >= MAX_EVENTS_PER_POLL) {
                    overflow = true;
                    break;
                }
                events.getNextEvent(e);
                int type = e.getEventType();
                String pkg = e.getPackageName();
                if (pkg == null) continue;
                if (type == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    reducer.foreground(pkg, e.getClassName(), e.getTimeStamp(),
                            getPackageName());
                    recentActivity.recordForeground(pkg, e.getClassName(), e.getTimeStamp(),
                            getPackageName());
                } else if (type == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                    reducer.background(pkg, e.getClassName(), e.getTimeStamp());
                }
            }
        }
        lastScanEnd = now;

        if (!overflow && reducer.currentPackage.length() != 0) {
            boolean full = reducer.currentClass.length() != 0;
            latest = new Snapshot(full ? "监测中" : "监测中（仅识别到应用）",
                    reducer.currentPackage, reducer.currentClass,
                    reducer.lastOtherPackage, reducer.lastOtherClass,
                    reducer.changedMs, now,
                    recentActivity.lastNonLauncher(), recentActivity.lastEvents(6),
                    access, "usage_events", full ? "full_context" : "package_only");
            return;
        }

        // Package-level fallback deliberately does NOT invent an Activity.
        // N1 may use it only as positive playback context; it can never grant
        // system/app-home or paused free time.
        String fallback = fallbackPackage(manager, now);
        if (fallback.length() != 0) {
            latest = new Snapshot("监测中（仅识别到应用）",
                    fallback, "", "", "", now, now,
                    recentActivity.lastNonLauncher(), recentActivity.lastEvents(6),
                    access, "usage_stats",
                    overflow ? "package_only_after_overflow" : "package_only");
            return;
        }

        String status;
        if (overflow) status = "event_overflow";
        else if (!"allowed".equals(access)) status = "permission_unconfirmed";
        else if (events == null) status = "events_unavailable";
        else status = "no_foreground";
        latest = Snapshot.diagnostic("监测中（前台待确认）", now, access, status);
    }

    @Override
    public void onDestroy() {
        running = false;
        if (handler != null) {
            handler.removeCallbacksAndMessages(null);
            handler = null;
        }
        if (worker != null) {
            worker.quitSafely();
            worker = null;
        }
        if (reportHandler != null) {
            reportHandler.removeCallbacksAndMessages(null);
            reportHandler = null;
        }
        if (reportWorker != null) {
            reportWorker.quitSafely();
            reportWorker = null;
        }
        recentActivity.clear();
        latest = Snapshot.empty("已停止");
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
