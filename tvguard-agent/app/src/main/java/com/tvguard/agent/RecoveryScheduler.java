package com.tvguard.agent;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import java.util.List;

/**
 * Persisted, low-frequency boot fallback for vendor TVs that may suppress
 * third-party BOOT_COMPLETED delivery. This is not the primary watchdog.
 */
final class RecoveryScheduler {
    static final int JOB_ID = 7025;
    static final long PERIOD_MS = 15L * 60L * 1000L;

    private RecoveryScheduler() { }

    static boolean ensureScheduled(Context context) {
        if (!MonitorService.isEnabled(context)) return false;
        JobScheduler scheduler =
                (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (scheduler == null) return false;
        JobInfo job = new JobInfo.Builder(JOB_ID,
                new ComponentName(context, RecoveryJobService.class))
                .setPersisted(true)
                .setPeriodic(PERIOD_MS)
                .build();
        return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS;
    }

    static void cancel(Context context) {
        JobScheduler scheduler =
                (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (scheduler != null) scheduler.cancel(JOB_ID);
    }

    static boolean isScheduled(Context context) {
        JobScheduler scheduler =
                (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (scheduler == null) return false;
        List<JobInfo> jobs = scheduler.getAllPendingJobs();
        if (jobs == null) return false;
        for (JobInfo job : jobs) {
            if (job.getId() == JOB_ID) return true;
        }
        return false;
    }
}
