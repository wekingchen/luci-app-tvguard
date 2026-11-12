package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class SamplingWindowTest {
    @Test public void freshProcessQueriesHistoryAndResetsState() {
        SamplingWindow w = SamplingWindow.plan(10000000L, 0L);
        assertTrue(w.reset);
        assertEquals(6400000L, w.fromMs);
    }

    @Test public void normalPollingReusesStateAndOverlaps() {
        SamplingWindow w = SamplingWindow.plan(10000000L, 9995000L);
        assertFalse(w.reset);
        assertEquals(9994000L, w.fromMs);
    }

    @Test public void longPauseInvalidatesPriorForeground() {
        SamplingWindow w = SamplingWindow.plan(10000000L, 9000000L);
        assertTrue(w.reset);
        assertEquals(9700000L, w.fromMs);
    }

    @Test public void clockRollbackInvalidatesPriorForeground() {
        SamplingWindow w = SamplingWindow.plan(10000000L, 12000000L);
        assertTrue(w.reset);
        assertEquals(6400000L, w.fromMs);
    }

    @Test public void earlyUptimeIsNonnegative() {
        SamplingWindow w = SamplingWindow.plan(3000L, 0L);
        assertEquals(0L, w.fromMs);
    }
}
