package com.tvguard.agent;

import android.app.AppOpsManager;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;

/**
 * Volatile, bounded observer. No file I/O, database, log, network or event queue.
 * UsageEvents are sampled for short time windows only. States are hints, never billing.
 */
public final class MonitorService extends Service {
    private static final long SAMPLE_INTERVAL_MS = 5000L;
    private static final long INITIAL_LOOKBACK_MS = 60L * 60L * 1000L;
    private static final long MAX_RESUME_LOOKBACK_MS = 5L * 60L * 1000L;
    private static final int MAX_EVENTS_PER_POLL = 4096;
    private static volatile Snapshot latest = Snapshot.empty("未启动");
    private HandlerThread worker;
    private Handler handler;
    private long lastScanEnd;

    public static final class Snapshot {
        public final String state;
        public final String currentPackage;
        public final String currentClass;
        public final String lastOtherPackage;
        public final String lastOtherClass;
        public final long changedMs;
        public final long sampledMs;

        Snapshot(String state, String currentPackage, String currentClass,
                 String lastOtherPackage, String lastOtherClass,
                 long changedMs, long sampledMs) {
            this.state = state;
            this.currentPackage = currentPackage;
            this.currentClass = currentClass;
            this.lastOtherPackage = lastOtherPackage;
            this.lastOtherClass = lastOtherClass;
            this.changedMs = changedMs;
            this.sampledMs = sampledMs;
        }

        static Snapshot empty(String state) {
            return new Snapshot(state, "", "", "", "", 0L, 0L);
        }
    }

    public static Snapshot snapshot() {
        return latest;
    }

    public static boolean isEnabled(Context context) {
        return context.getSharedPreferences("control", Context.MODE_PRIVATE)
                .getBoolean("enabled", false);
    }

    public static boolean setEnabled(Context context, boolean enabled) {
        SharedPreferences.Editor editor =
                context.getSharedPreferences("control", Context.MODE_PRIVATE)
                        .edit().putBoolean("enabled", enabled);
        return editor.commit(); // One tiny write only on explicit user action.
    }

    public static boolean hasUsageAccess(Context context) {
        AppOpsManager appOps =
                (AppOpsManager) context.getSystemService(Context.APP_OPS_SERVICE);
        return appOps != null &&
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                        Process.myUid(), context.getPackageName())
                        == AppOpsManager.MODE_ALLOWED;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        worker = new HandlerThread("tvguard-observe", Process.THREAD_PRIORITY_BACKGROUND);
        worker.start();
        handler = new Handler(worker.getLooper());
        handler.post(poll);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!isEnabled(this)) {
            stopSelf();
            return START_NOT_STICKY;
        }
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
                latest = new Snapshot("读取失败：" + failure.getClass().getSimpleName(),
                        before.currentPackage, before.currentClass,
                        before.lastOtherPackage, before.lastOtherClass,
                        before.changedMs, System.currentTimeMillis());
            }
            if (handler != null) {
                handler.postDelayed(this, SAMPLE_INTERVAL_MS);
            }
        }
    };

    private void sampleOnce() {
        long now = System.currentTimeMillis();
        if (!hasUsageAccess(this)) {
            latest = Snapshot.empty("等待使用情况权限");
            lastScanEnd = 0;
            return;
        }
        UsageStatsManager manager =
                (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        if (manager == null) {
            latest = Snapshot.empty("系统未提供 UsageStats 服务");
            return;
        }
        boolean coldStart = lastScanEnd == 0L || now < lastScanEnd;
        long from = coldStart ? Math.max(0L, now - INITIAL_LOOKBACK_MS)
                : Math.max(lastScanEnd - 1000L, now - MAX_RESUME_LOOKBACK_MS);
        Snapshot previous = latest;
        ForegroundReducer reducer = new ForegroundReducer(
                coldStart ? "" : previous.currentPackage,
                coldStart ? "" : previous.currentClass,
                coldStart ? "" : previous.lastOtherPackage,
                coldStart ? "" : previous.lastOtherClass,
                coldStart ? 0L : previous.changedMs);
        UsageEvents events = manager.queryEvents(from, now + 1000L);
        if (events == null) {
            latest = Snapshot.empty("系统未返回使用事件");
            lastScanEnd = 0L;
            return;
        }
        UsageEvents.Event e = new UsageEvents.Event();
        int processed = 0;
        boolean overflow = false;
        while (events.hasNextEvent()) {
            if (processed++ >= MAX_EVENTS_PER_POLL) {
                overflow = true;
                break;
            }
            events.getNextEvent(e);
            int type = e.getEventType();
            String pkg = e.getPackageName();
            if (pkg == null) {
                continue;
            }
            if (type == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                reducer.foreground(pkg, e.getClassName(), e.getTimeStamp(),
                        getPackageName());
            } else if (type == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                reducer.background(pkg, e.getClassName(), e.getTimeStamp());
            }
        }
        lastScanEnd = now;
        latest = new Snapshot(overflow ? "事件超限，结果不完整" : "监测中",
                reducer.currentPackage, reducer.currentClass,
                reducer.lastOtherPackage, reducer.lastOtherClass,
                reducer.changedMs, now);
    }

    @Override
    public void onDestroy() {
        if (handler != null) {
            handler.removeCallbacksAndMessages(null);
            handler = null;
        }
        if (worker != null) {
            worker.quitSafely();
            worker = null;
        }
        latest = Snapshot.empty("已停止");
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
