package com.tvguard.agent;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;

/**
 * System-owned recovery entry point.
 *
 * Fast non-persisted jobs arm the alternate ID before doing any other work, so
 * a process kill still leaves the next recovery point inside system_server.
 * The persisted job exists only to re-seed the fast chain after reboot.
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
            RecoveryScheduler.scheduleNextFast(this, params.getJobId());
        }

        AccessibilityRecovery.reconcile(this);
        if (!MonitorService.isRunning()) {
            startService(new Intent(this, MonitorService.class));
        }
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
