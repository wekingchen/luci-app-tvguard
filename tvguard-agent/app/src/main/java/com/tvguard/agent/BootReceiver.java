package com.tvguard.agent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        boolean recoveryEvent = Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action);
        if (recoveryEvent && MonitorService.isEnabled(context)) {
            context.startService(new Intent(context, MonitorService.class));
            WatchdogReceiver.schedule(context);
            RecoveryScheduler.ensureScheduled(context);
        }
    }
}
