package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class ForegroundReducerTest {
    private ForegroundReducer blank() {
        return new ForegroundReducer("", "", "", "", 0L);
    }

    @Test public void firstVideoAppCaptured() {
        ForegroundReducer s = blank();
        s.foreground("com.gitvdemo.video", "HomeActivity", 100L, "com.tvguard.agent");
        assertEquals("com.gitvdemo.video", s.currentPackage);
        assertEquals("HomeActivity", s.currentClass);
        assertEquals(s.currentPackage, s.lastOtherPackage);
    }

    @Test public void switchingAppsPreservesNewAppAgainstLateBackground() {
        ForegroundReducer s = blank();
        s.foreground("com.ktcp.video", "Home", 100L, "com.tvguard.agent");
        s.foreground("org.smarttube.stable", "Player", 110L, "com.tvguard.agent");
        s.background("com.ktcp.video", "Home", 120L);
        assertEquals("org.smarttube.stable", s.currentPackage);
    }

    @Test public void samePackageActivitySwitchPreservesNewPlayer() {
        ForegroundReducer s = blank();
        s.foreground("com.gitvdemo.video", "HomeActivity", 100L, "com.tvguard.agent");
        s.foreground("com.gitvdemo.video", "PlayerActivity", 200L, "com.tvguard.agent");
        s.background("com.gitvdemo.video", "HomeActivity", 201L);
        assertEquals("com.gitvdemo.video", s.currentPackage);
        assertEquals("PlayerActivity", s.currentClass);
    }

    @Test public void actualBackgroundClearsCurrentButKeepsLastExternal() {
        ForegroundReducer s = blank();
        s.foreground("com.gitvdemo.video", "Player", 100L, "com.tvguard.agent");
        s.background("com.gitvdemo.video", "Player", 110L);
        assertEquals("", s.currentPackage);
        assertEquals("com.gitvdemo.video", s.lastOtherPackage);
    }

    @Test public void returningToAgentDoesNotOverwriteLastVideo() {
        ForegroundReducer s = blank();
        s.foreground("org.smarttube.stable", "Player", 100L, "com.tvguard.agent");
        s.foreground("com.tvguard.agent", "MainActivity", 200L, "com.tvguard.agent");
        assertEquals("org.smarttube.stable", s.lastOtherPackage);
        assertEquals("com.tvguard.agent", s.currentPackage);
    }

    @Test public void oldEventsIgnored() {
        ForegroundReducer s = blank();
        s.foreground("com.ktcp.video", "Activity", 200L, "com.tvguard.agent");
        s.background("com.ktcp.video", "Activity", 150L);
        s.foreground("com.gitvdemo.video", "Activity", 150L, "com.tvguard.agent");
        assertEquals("com.ktcp.video", s.currentPackage);
        assertEquals(200L, s.changedMs);
    }

    @Test public void malformedNullInputDoesNotCrash() {
        ForegroundReducer s = blank();
        s.foreground(null, null, 100L, "com.tvguard.agent");
        s.background(null, null, 110L);
        assertEquals("", s.currentPackage);
        s.foreground("com.example", null, 120L, "com.tvguard.agent");
        assertEquals("", s.currentClass);
    }
}
