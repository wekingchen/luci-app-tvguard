package com.tvguard.agent;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import java.util.List;

/**
 * System-owned fast recovery chain for vendor TVs that may kill third-party
 * background processes and suppress alarm broadcasts while the process is dead.
 *
 * Uses alternating persisted one-shot jobs instead of a periodic job. Each
 * RecoveryJobService execution schedules the next job before doing any work,
 * so a killed Agent can be recreated by system_server without relying on the
 * Agent process itself being alive.
 */
final class RecoveryScheduler {
    static final int JOB_ID_A = 7025;
    static final int JOB_ID_B = 7026;
    static final long MIN_LATENCY_MS = 20000L;
    static final long DEADLINE_MS = 30000L;

    private RecoveryScheduler() { }

    private static JobScheduler scheduler(Context context) {
        return (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
    }

    private static boolean isRecoveryId(int id) {
        return id == JOB_ID_A || id == JOB_ID_B;
    }

    private static boolean schedule(JobScheduler scheduler, Context context, int jobId) {
        JobInfo job = new JobInfo.Builder(jobId,
                new ComponentName(context, RecoveryJobService.class))
                .setPersisted(true)
                .setMinimumLatency(MIN_LATENCY_MS)
                .setOverrideDeadline(DEADLINE_MS)
                .build();
        return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS;
    }

    static boolean ensureScheduled(Context context) {
        if (!MonitorService.isEnabled(context)) return false;
        JobScheduler scheduler = scheduler(context);
        if (scheduler == null) return false;

        List<JobInfo> jobs = scheduler.getAllPendingJobs();
        if (jobs != null) {
            for (JobInfo job : jobs) {
                if (!isRecoveryId(job.getId())) continue;
                if (!job.isPeriodic()) return true;
                // v0.2.5 migration: replace the old 15-minute periodic job.
                scheduler.cancel(job.getId());
            }
        }
        return schedule(scheduler, context, JOB_ID_A);
    }

    static boolean scheduleNext(Context context, int currentJobId) {
        if (!MonitorService.isEnabled(context)) return false;
        JobScheduler scheduler = scheduler(context);
        if (scheduler == null) return false;
        int nextId = currentJobId == JOB_ID_A ? JOB_ID_B : JOB_ID_A;
        return schedule(scheduler, context, nextId);
    }

    static void cancel(Context context) {
        JobScheduler scheduler = scheduler(context);
        if (scheduler != null) {
            scheduler.cancel(JOB_ID_A);
            scheduler.cancel(JOB_ID_B);
        }
    }

    static boolean isScheduled(Context context) {
        JobScheduler scheduler = scheduler(context);
        if (scheduler == null) return false;
        List<JobInfo> jobs = scheduler.getAllPendingJobs();
        if (jobs == null) return false;
        for (JobInfo job : jobs) {
            if (isRecoveryId(job.getId())) return true;
        }
        return false;
    }
}
