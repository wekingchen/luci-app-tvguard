package com.tvguard.agent;

/** Pure Java bounded query window; invalidates stale foreground after gaps. */
final class SamplingWindow {
    static final long INITIAL_LOOKBACK_MS = 60L * 60L * 1000L;
    static final long MAX_GAP_MS = 5L * 60L * 1000L;
    static final long OVERLAP_MS = 1000L;
    final long fromMs;
    final boolean reset;

    SamplingWindow(long fromMs, boolean reset) {
        this.fromMs = fromMs;
        this.reset = reset;
    }

    static SamplingWindow plan(long now, long previousEnd) {
        if (previousEnd <= 0L || previousEnd > now) {
            return new SamplingWindow(Math.max(0L, now - INITIAL_LOOKBACK_MS), true);
        }
        if (now - previousEnd > MAX_GAP_MS) {
            return new SamplingWindow(Math.max(0L, now - MAX_GAP_MS), true);
        }
        long from = Math.max(0L, Math.max(previousEnd - OVERLAP_MS,
                now - MAX_GAP_MS));
        return new SamplingWindow(from, false);
    }
}
