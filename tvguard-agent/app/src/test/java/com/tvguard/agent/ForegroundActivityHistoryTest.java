package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class ForegroundActivityHistoryTest {
    @Test public void launcherAgentAndArbitraryAppsRemainGeneric() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        h.recordForeground("com.mitv.tvhome", "Home", 100L, "com.tvguard.agent");
        h.recordForeground("com.example.alpha", "Browse", 200L, "com.tvguard.agent");
        h.recordForeground("com.example.alpha", "Watch", 300L, "com.tvguard.agent");
        h.recordForeground("com.mitv.tvhome", "Home", 400L, "com.tvguard.agent");
        h.recordForeground("com.tvguard.agent", "MainActivity", 500L, "com.tvguard.agent");
        assertEquals("com.example.alpha", h.lastNonLauncher().packageName);
        assertEquals("Watch", h.lastNonLauncher().activityName);
        assertEquals(4, h.size());
    }

    @Test public void arbitraryUnknownPackageIsPreservedWithoutWhitelist() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        h.recordForeground("org.brand.newstream", "AnyActivity", 100L, "com.tvguard.agent");
        h.recordForeground("com.mitv.tvhome", "Home", 200L, "com.tvguard.agent");
        assertEquals("org.brand.newstream", h.lastNonLauncher().packageName);
        assertEquals("AnyActivity", h.lastNonLauncher().activityName);
    }

    @Test public void launcherAndAgentAloneDoNotProduceNonLauncher() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        h.recordForeground("com.mitv.tvhome", "Home", 100L, "com.tvguard.agent");
        h.recordForeground("com.tvguard.agent", "MainActivity", 200L, "com.tvguard.agent");
        assertNull(h.lastNonLauncher());
    }

    @Test public void boundedMemoryAndNewestFirst() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        for (int i = 1; i <= 10000; i++) {
            h.recordForeground("com.example.test", "Page" + i, i, "com.tvguard.agent");
        }
        assertEquals(24, h.size());
        assertEquals("Page10000", h.lastEvents(6)[0].activityName);
        assertEquals("Page9995", h.lastEvents(6)[5].activityName);
        assertEquals(6, h.lastEvents(6).length);
    }

    @Test public void overlappedPollingDoesNotDuplicate() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        h.recordForeground("com.example.any", "Home", 100L, "com.tvguard.agent");
        h.recordForeground("com.example.any", "Home", 100L, "com.tvguard.agent");
        assertEquals(1, h.size());
    }

    @Test public void invalidationClearsHistoricalEvidence() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        h.recordForeground("com.example.any", "Watch", 100L, "com.tvguard.agent");
        h.clear();
        assertNull(h.lastNonLauncher());
        assertEquals(0, h.size());
    }

    @Test public void nullAndExtremelyLongActivityAreBounded() {
        ForegroundActivityHistory h = new ForegroundActivityHistory();
        h.recordForeground(null, null, 100L, "com.tvguard.agent");
        assertEquals(0, h.size());
        StringBuilder longName = new StringBuilder();
        for (int i=0; i<1000; i++) longName.append('X');
        h.recordForeground("com.example.any", longName.toString(), 200L, "com.tvguard.agent");
        assertEquals(160, h.lastNonLauncher().activityName.length());
    }
}
