package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class HeartbeatStateTest {
    @Test public void recentUsageSnapshotIsFresh() {
        assertTrue(HeartbeatState.isFresh(120000L, 115000L));
        assertTrue(HeartbeatState.isFresh(120000L, 100000L));
    }

    @Test public void staleUsageSnapshotCannotMasqueradeAsPlaying() {
        assertFalse(HeartbeatState.isFresh(120001L, 100000L));
        assertFalse(HeartbeatState.isFresh(300000L, 120000L));
    }

    @Test public void unknownOrFutureTimestampIsNotFresh() {
        assertFalse(HeartbeatState.isFresh(100000L, 0L));
        assertFalse(HeartbeatState.isFresh(100000L, 100001L));
    }
}
