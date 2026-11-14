package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class AccessibilityRecoveryPolicyTest {
    @Test public void connectedOrMonitorOffNeedsNoRecovery() {
        assertEquals(AccessibilityRecoveryPolicy.NONE,
                AccessibilityRecoveryPolicy.decide(false, true, true, false,
                        true, true, 60000L, 60000L));
        assertEquals(AccessibilityRecoveryPolicy.NONE,
                AccessibilityRecoveryPolicy.decide(true, true, true, true,
                        true, true, 60000L, 60000L));
    }

    @Test public void configuredUnboundGetsGraceThenFrameworkNudge() {
        assertEquals(AccessibilityRecoveryPolicy.NONE,
                AccessibilityRecoveryPolicy.decide(true, true, true, false,
                        true, false, 10000L, Long.MAX_VALUE));
        assertEquals(AccessibilityRecoveryPolicy.NUDGE,
                AccessibilityRecoveryPolicy.decide(true, true, true, false,
                        true, false, 20000L, Long.MAX_VALUE));
        assertEquals(AccessibilityRecoveryPolicy.NONE,
                AccessibilityRecoveryPolicy.decide(true, true, true, false,
                        true, false, 60000L, 10000L));
    }

    @Test public void staleBoundFlagCannotMaskDisabledGlobalOrMissingAuthorization() {
        assertEquals(AccessibilityRecoveryPolicy.REPAIR_SECURE_SETTINGS,
                AccessibilityRecoveryPolicy.decide(true, false, true, true,
                        true, true, 1000L, Long.MAX_VALUE));
        assertEquals(AccessibilityRecoveryPolicy.REPAIR_SECURE_SETTINGS,
                AccessibilityRecoveryPolicy.decide(true, true, false, true,
                        true, true, 1000L, Long.MAX_VALUE));
    }

    @Test public void missingAuthorizationRepairsOnlyAfterPriorOptInAndSecureGrant() {
        assertEquals(AccessibilityRecoveryPolicy.NONE,
                AccessibilityRecoveryPolicy.decide(true, true, false, false,
                        false, true, 60000L, Long.MAX_VALUE));
        assertEquals(AccessibilityRecoveryPolicy.NONE,
                AccessibilityRecoveryPolicy.decide(true, true, false, false,
                        true, false, 60000L, Long.MAX_VALUE));
        assertEquals(AccessibilityRecoveryPolicy.REPAIR_SECURE_SETTINGS,
                AccessibilityRecoveryPolicy.decide(true, true, false, false,
                        true, true, 60000L, Long.MAX_VALUE));
        assertEquals(AccessibilityRecoveryPolicy.REPAIR_SECURE_SETTINGS,
                AccessibilityRecoveryPolicy.decide(true, false, true, false,
                        true, true, 60000L, Long.MAX_VALUE));
    }
}
