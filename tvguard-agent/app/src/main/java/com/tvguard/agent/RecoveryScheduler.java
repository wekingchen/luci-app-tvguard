package com.tvguard.agent;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import java.util.List;

/**
 * Two-tier recovery owned by system_server:
 *
 * 1) one low-frequency persisted periodic job survives reboot;
 * 2) alternating non-persisted one-shot jobs provide fast process-death recovery
 *    while the TV is running, without rewriting persisted JobStore every cycle.
 */
final class RecoveryScheduler {
    static final int PERSISTED_JOB_ID = 7025;
    static final int FAST_JOB_ID_A = 7026;
    static final int FAST_JOB_ID_B = 7027;
    static final long PERSISTED_PERIOD_MS = 15L * 60L * 1000L;
    static final long FAST_MIN_LATENCY_MS = 20000L;
    static final long FAST_DEADLINE_MS = 30000L;

    private RecoveryScheduler() { }

    private static JobScheduler scheduler(Context context) {
        return (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
    }

    private static boolean isFastId(int id) {
        return id == FAST_JOB_ID_A || id == FAST_JOB_ID_B;
    }

    private static boolean hasJob(JobScheduler scheduler, int jobId) {
        List<JobInfo> jobs = scheduler.getAllPendingJobs();
        if (jobs == null) return false;
        for (JobInfo job : jobs) {
            if (job.getId() == jobId) return true;
        }
        return false;
    }

    private static boolean hasFastJob(JobScheduler scheduler) {
        List<JobInfo> jobs = scheduler.getAllPendingJobs();
        if (jobs == null) return false;
        for (JobInfo job : jobs) {
            if (isFastId(job.getId())) return true;
        }
        return false;
    }

    private static boolean schedulePersistedFallback(Context context,
                                                       JobScheduler scheduler) {
        if (hasJob(scheduler, PERSISTED_JOB_ID)) return true;
        JobInfo job = new JobInfo.Builder(PERSISTED_JOB_ID,
                new ComponentName(context, RecoveryJobService.class))
                .setPersisted(true)
                .setPeriodic(PERSISTED_PERIOD_MS)
                .build();
        return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS;
    }

    private static boolean scheduleFast(Context context, JobScheduler scheduler, int jobId) {
        JobInfo job = new JobInfo.Builder(jobId,
                new ComponentName(context, RecoveryJobService.class))
                .setPersisted(false)
                .setMinimumLatency(FAST_MIN_LATENCY_MS)
                .setOverrideDeadline(FAST_DEADLINE_MS)
                .build();
        return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS;
    }

    static boolean ensureScheduled(Context context) {
        if (!MonitorService.isEnabled(context)) return false;
        JobScheduler scheduler = scheduler(context);
        if (scheduler == null) return false;

        boolean persisted = schedulePersistedFallback(context, scheduler);
        boolean fast = hasFastJob(scheduler)
                || scheduleFast(context, scheduler, FAST_JOB_ID_A);
        return persisted && fast;
    }

    static boolean scheduleNextFast(Context context, int currentJobId) {
        if (!MonitorService.isEnabled(context)) return false;
        JobScheduler scheduler = scheduler(context);
        if (scheduler == null) return false;
        int nextId = currentJobId == FAST_JOB_ID_A ? FAST_JOB_ID_B : FAST_JOB_ID_A;
        return scheduleFast(context, scheduler, nextId);
    }

    static void cancel(Context context) {
        JobScheduler scheduler = scheduler(context);
        if (scheduler != null) {
            scheduler.cancel(PERSISTED_JOB_ID);
            scheduler.cancel(FAST_JOB_ID_A);
            scheduler.cancel(FAST_JOB_ID_B);
        }
    }

    static boolean isScheduled(Context context) {
        JobScheduler scheduler = scheduler(context);
        if (scheduler == null) return false;
        return hasJob(scheduler, PERSISTED_JOB_ID) && hasFastJob(scheduler);
    }
}
