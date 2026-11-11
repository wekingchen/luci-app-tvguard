package com.tvguard.agent;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;

/**
 * Low-frequency system-owned fallback. If monitoring is enabled, ensure the
 * monitor service and exact non-wakeup service alarm are both present.
 */
public final class RecoveryJobService extends JobService {
    @Override
    public boolean onStartJob(JobParameters params) {
        if (!MonitorService.isEnabled(this)) {
            RecoveryScheduler.cancel(this);
            WatchdogReceiver.cancel(this);
            return false;
        }

        if (!MonitorService.isRunning()) {
            startService(new Intent(this, MonitorService.class));
        }
        WatchdogReceiver.schedule(this);
        return false;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return false;
    }
}
