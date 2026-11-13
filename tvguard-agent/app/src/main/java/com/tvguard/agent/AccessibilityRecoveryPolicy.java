package com.tvguard.agent;

/** Pure decision policy for AccessibilityService recovery. */
final class AccessibilityRecoveryPolicy {
    static final int NONE = 0;
    static final int NUDGE = 1;
    static final int REPAIR_SECURE_SETTINGS = 2;

    static final long UNBOUND_GRACE_MS = 15000L;
    static final long NUDGE_COOLDOWN_MS = 30000L;

    private AccessibilityRecoveryPolicy() { }

    static int decide(boolean monitorEnabled, boolean globalEnabled,
                      boolean configured, boolean connected,
                      boolean managedOptIn, boolean canWriteSecure,
                      long unboundDurationMs, long sinceLastNudgeMs) {
        if (!monitorEnabled || connected) return NONE;
        if (!globalEnabled || !configured) {
            return managedOptIn && canWriteSecure
                    ? REPAIR_SECURE_SETTINGS : NONE;
        }
        if (unboundDurationMs >= UNBOUND_GRACE_MS
                && sinceLastNudgeMs >= NUDGE_COOLDOWN_MS) {
            return NUDGE;
        }
        return NONE;
    }
}
