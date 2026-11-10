package com.tvguard.agent;

import android.app.AppOpsManager;
import android.app.Notification;
import android.app.PendingIntent;
import android.media.AudioManager;
import android.os.PowerManager;
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
    private static final int NOTIFICATION_ID = 1001;
    private static final int MAX_EVENTS_PER_POLL = 4096;
    private static volatile Snapshot latest = Snapshot.empty("未启动");
    private HandlerThread worker;
    private Handler handler;
    private long lastScanEnd;
    private final VideoActivityHistory recentActivity = new VideoActivityHistory();

    public static final class Snapshot {
        public final String state;
        public final String currentPackage;
        public final String currentClass;
        public final String lastOtherPackage;
        public final String lastOtherClass;
        public final long changedMs;
        public final long sampledMs;
        public final VideoActivityHistory.Event recentVideo;
        public final VideoActivityHistory.Event recentNonLauncher;
        public final VideoActivityHistory.Event[] timeline;

        Snapshot(String state, String currentPackage, String currentClass,
                 String lastOtherPackage, String lastOtherClass,
                 long changedMs, long sampledMs,
                 VideoActivityHistory.Event recentVideo,
                 VideoActivityHistory.Event recentNonLauncher,
                 VideoActivityHistory.Event[] timeline) {
            this.state = state;
            this.currentPackage = currentPackage;
            this.currentClass = currentClass;
            this.lastOtherPackage = lastOtherPackage;
            this.lastOtherClass = lastOtherClass;
            this.changedMs = changedMs;
            this.sampledMs = sampledMs;
            this.recentVideo = recentVideo;
            this.recentNonLauncher = recentNonLauncher;
            this.timeline = timeline.clone();
        }

        static Snapshot empty(String state) {
            return new Snapshot(state, "", "", "", "", 0L, 0L, null, null,
                    new VideoActivityHistory.Event[0]);
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
        // The user explicitly enabled monitoring. A standard visible foreground
        // notification lowers background eviction risk without hidden keep-alive.
        // Android/vendor policy can still terminate the process.
        Intent openApp = new Intent(this, MainActivity.class);
        PendingIntent open = PendingIntent.getActivity(this, 0, openApp,
                PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification = new Notification.Builder(this)
                .setSmallIcon(android.R.drawable.ic_menu_info_details)
                .setContentTitle("TVGuard 助手")
                .setContentText("前台应用监测中 · 无运行日志")
                .setContentIntent(open)
                .setOngoing(true)
                .setPriority(Notification.PRIORITY_MIN)
                .build();
        startForeground(NOTIFICATION_ID, notification);
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
                latest = new Snapshot("读取失败：" + failure.getClass().getSimpleName(),
                        "", "", "", "", 0L, before.sampledMs,
                        null, null, new VideoActivityHistory.Event[0]);
                recentActivity.clear();
                lastScanEnd = 0L;
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
            recentActivity.clear();
            lastScanEnd = 0;
            return;
        }
        UsageStatsManager manager =
                (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        if (manager == null) {
            latest = Snapshot.empty("系统未提供 UsageStats 服务");
            recentActivity.clear();
            lastScanEnd = 0;
            return;
        }
        SamplingWindow window = SamplingWindow.plan(now, lastScanEnd);
        if (window.reset) {
            // Cold start can rebuild meaningful history from Android UsageEvents.
            // No event is persisted by TVGuard itself.
            recentActivity.clear();
        }
        Snapshot previous = latest;
        // A stale foreground must not survive suspension or clock rollback.
        ForegroundReducer reducer = new ForegroundReducer(
                window.reset ? "" : previous.currentPackage,
                window.reset ? "" : previous.currentClass,
                window.reset ? "" : previous.lastOtherPackage,
                window.reset ? "" : previous.lastOtherClass,
                window.reset ? 0L : previous.changedMs);
        UsageEvents events = manager.queryEvents(window.fromMs, now + 1000L);
        if (events == null) {
            latest = Snapshot.empty("系统未返回使用事件");
            recentActivity.clear();
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
                recentActivity.recordForeground(pkg, e.getClassName(), e.getTimeStamp(),
                        getPackageName());
            } else if (type == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                reducer.background(pkg, e.getClassName(), e.getTimeStamp());
            }
        }
        lastScanEnd = now;
        if (overflow) {
            // A partial event window is not valid proof of foreground state.
            recentActivity.clear();
            latest = new Snapshot("事件超限，前台待确认", "", "", "", "", 0L, now,
                    null, null, new VideoActivityHistory.Event[0]);
            return;
        }
        String state = reducer.currentPackage.length() == 0
                ? "监测中（前台待确认）" : "监测中";
        latest = new Snapshot(state,
                reducer.currentPackage, reducer.currentClass,
                reducer.lastOtherPackage, reducer.lastOtherClass,
                reducer.changedMs, now,
                recentActivity.lastVideo(),
                recentActivity.lastNonLauncher(),
                recentActivity.lastEvents(6));
        // Android 6 provides only coarse audio/screen hints, not a universal
        // playback/paused API. They must never directly authorize billing.
        AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        PowerManager screen = (PowerManager) getSystemService(Context.POWER_SERVICE);
        boolean activeAudio = audio != null && audio.isMusicActive();
        boolean interactive = screen != null && screen.isInteractive();
        BridgeClient.maybeSend(this, reducer.currentPackage, reducer.currentClass,
                activeAudio, interactive, now);
    }

    @Override
    public void onDestroy() {
        stopForeground(true);
        if (handler != null) {
            handler.removeCallbacksAndMessages(null);
            handler = null;
        }
        if (worker != null) {
            worker.quitSafely();
            worker = null;
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
