package com.tvguard.agent;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;

/**
 * System-owned recovery entry point. Fast non-persisted jobs re-arm each other
 * while the TV is running; the low-frequency persisted job only survives boot
 * and re-seeds the fast chain when needed.
 */
public final class RecoveryJobService extends JobService {
    @Override
    public boolean onStartJob(JobParameters params) {
        if (!MonitorService.isEnabled(this)) {
            RecoveryScheduler.cancel(this);
            return false;
        }

        if (params.getJobId() == RecoveryScheduler.PERSISTED_JOB_ID) {
            RecoveryScheduler.ensureFastScheduled(this);
        } else {
            // Arm the next in-memory recovery point before doing any other work.
            RecoveryScheduler.scheduleNextFast(this, params.getJobId());
        }

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
