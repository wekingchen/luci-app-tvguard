package com.tvguard.agent;

/** Pure Java freshness gate: never publish an old Activity as current. */
final class HeartbeatState {
    static final long MAX_SAMPLE_AGE_MS = 20000L;

    private HeartbeatState() { }

    static boolean isFresh(long nowMs, long sampledMs) {
        return nowMs >= sampledMs && sampledMs > 0L &&
                nowMs - sampledMs <= MAX_SAMPLE_AGE_MS;
    }
}
