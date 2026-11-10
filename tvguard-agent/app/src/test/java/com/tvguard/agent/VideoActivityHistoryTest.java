package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class VideoActivityHistoryTest {
    @Test public void homeVideoPlayerLauncherAgentStillRemembersPlayer() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground("com.mitv.tvhome", "NewMyAppActivity", 100L, "com.tvguard.agent");
        h.recordForeground("com.gitvdemo.video", "HomeActivity", 200L, "com.tvguard.agent");
        h.recordForeground("com.gitvdemo.video", "PlayerActivity", 300L, "com.tvguard.agent");
        h.recordForeground("com.mitv.tvhome", "NewMyAppActivity", 400L, "com.tvguard.agent");
        h.recordForeground("com.tvguard.agent", "MainActivity", 500L, "com.tvguard.agent");
        assertNotNull(h.lastVideo());
        assertEquals("PlayerActivity", h.lastVideo().activityName);
        assertEquals(300L, h.lastVideo().timeMs);
        assertEquals("com.gitvdemo.video", h.lastNonLauncher().packageName);
        assertEquals(4, h.size());
    }

    @Test public void videoAppHomeAfterPlayerBecomesLastObservedVideoPage() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground("com.ktcp.video", "PlayerActivity", 200L, "com.tvguard.agent");
        h.recordForeground("com.ktcp.video", "HomeActivity", 300L, "com.tvguard.agent");
        h.recordForeground("com.mitv.tvhome", "MainActivity", 400L, "com.tvguard.agent");
        assertEquals("HomeActivity", h.lastVideo().activityName);
    }

    @Test public void launcherAndAgentAloneDoNotProduceVideo() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground("com.mitv.tvhome", "Home", 100L, "com.tvguard.agent");
        h.recordForeground("com.tvguard.agent", "MainActivity", 200L, "com.tvguard.agent");
        assertNull(h.lastVideo());
        assertNull(h.lastNonLauncher());
    }

    @Test public void unknownVideoAppIsStillVisibleAsNonLauncher() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground("org.some.newvideo", "WatchActivity", 100L, "com.tvguard.agent");
        h.recordForeground("com.mitv.tvhome", "Home", 200L, "com.tvguard.agent");
        assertNull(h.lastVideo());
        assertEquals("org.some.newvideo", h.lastNonLauncher().packageName);
    }

    @Test public void boundedMemoryAndNewestFirst() {
        VideoActivityHistory h = new VideoActivityHistory();
        for (int i = 1; i <= 10000; i++) {
            h.recordForeground("com.example.test", "Page" + i, i, "com.tvguard.agent");
        }
        assertEquals(24, h.size());
        assertEquals("Page10000", h.lastEvents(6)[0].activityName);
        assertEquals("Page9995", h.lastEvents(6)[5].activityName);
        assertEquals(6, h.lastEvents(6).length);
    }

    @Test public void overlappedPollingDoesNotDuplicate() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground("com.ktcp.video", "Home", 100L, "com.tvguard.agent");
        h.recordForeground("com.ktcp.video", "Home", 100L, "com.tvguard.agent");
        assertEquals(1, h.size());
    }

    @Test public void invalidationClearsHistoricalEvidence() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground("com.gitvdemo.video", "PlayerActivity", 100L, "com.tvguard.agent");
        h.clear();
        assertNull(h.lastVideo());
        assertEquals(0, h.size());
    }

    @Test public void nullAndExtremelyLongActivityAreBounded() {
        VideoActivityHistory h = new VideoActivityHistory();
        h.recordForeground(null, null, 100L, "com.tvguard.agent");
        assertEquals(0, h.size());
        StringBuilder longName = new StringBuilder();
        for (int i=0; i<1000; i++) longName.append('X');
        h.recordForeground("com.ktcp.video", longName.toString(), 200L, "com.tvguard.agent");
        assertEquals(160, h.lastVideo().activityName.length());
    }
}
