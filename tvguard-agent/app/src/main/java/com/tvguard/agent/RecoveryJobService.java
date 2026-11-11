package com.tvguard.agent;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;

/**
 * System-owned recovery entry point. The next persisted one-shot job is armed
 * first, then the monitor service is restored only when the Agent process does
 * not already have it running.
 */
public final class RecoveryJobService extends JobService {
    @Override
    public boolean onStartJob(JobParameters params) {
        if (!MonitorService.isEnabled(this)) {
            RecoveryScheduler.cancel(this);
            return false;
        }

        // Arm the next system-owned recovery point before doing anything else.
        // Alternating IDs avoid replacing the currently executing job.
        RecoveryScheduler.scheduleNext(this, params.getJobId());

        if (!MonitorService.isRunning()) {
            startService(new Intent(this, MonitorService.class));
        }
        WatchdogReceiver.schedule(this);
        return false;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        if (MonitorService.isEnabled(this)) {
            RecoveryScheduler.ensureScheduled(this);
        }
        return false;
    }
}
