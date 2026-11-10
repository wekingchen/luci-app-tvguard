package com.tvguard.agent;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;

/**
 * Low-frequency recovery alarm for vendor background process eviction.
 *
 * Uses ELAPSED_REALTIME (non-wakeup), so a sleeping TV is not woken.
 * Android force-stop cancels alarms by platform design and still requires
 * an explicit user launch before monitoring can resume.
 */
public final class WatchdogReceiver extends BroadcastReceiver {
    static final long INTERVAL_MS = 30000L;
    static final String ACTION = "com.tvguard.agent.WATCHDOG";
    private static final int REQUEST_CODE = 7024;

    private static PendingIntent pending(Context context) {
        Intent intent = new Intent(context, WatchdogReceiver.class);
        intent.setAction(ACTION);
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT);
    }

    static void schedule(Context context) {
        AlarmManager manager =
                (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null || !MonitorService.isEnabled(context)) return;
        manager.setExact(AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + INTERVAL_MS, pending(context));
    }

    static void cancel(Context context) {
        AlarmManager manager =
                (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager != null) manager.cancel(pending(context));
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !ACTION.equals(intent.getAction())) return;
        if (!MonitorService.isEnabled(context)) {
            cancel(context);
            return;
        }
        context.startService(new Intent(context, MonitorService.class));
        schedule(context);
    }
}
