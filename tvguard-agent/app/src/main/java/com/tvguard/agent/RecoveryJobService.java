package com.tvguard.agent;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;

/**
 * System-owned persisted fallback. Runs at low frequency and only ensures the
 * foreground monitor service exists when monitoring was explicitly enabled.
 */
public final class RecoveryJobService extends JobService {
    @Override
    public boolean onStartJob(JobParameters params) {
        if (MonitorService.isEnabled(this)) {
            startService(new Intent(this, MonitorService.class));
            WatchdogReceiver.schedule(this);
        } else {
            RecoveryScheduler.cancel(this);
        }
        jobFinished(params, false);
        return false;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return false;
    }
}
