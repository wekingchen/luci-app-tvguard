package com.tvguard.agent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                && MonitorService.isEnabled(context)) {
            context.startService(new Intent(context, MonitorService.class));
            WatchdogReceiver.schedule(context);
        }
    }
}
