package com.tvguard.agent;

import org.junit.Test;
import static org.junit.Assert.*;

public final class BridgeProtocolTest {
    private static final String KEY = "0123456789abcdef0123456789abcdef";

    @Test public void privateLanTargetsAllowed() {
        assertTrue(BridgeProtocol.validEndpoint("http://192.168.101.2/cgi-bin/tvguard-agent"));
        assertTrue(BridgeProtocol.validEndpoint("http://10.0.0.1:8080/cgi-bin/tvguard-agent"));
        assertTrue(BridgeProtocol.validEndpoint("http://172.16.0.1/cgi-bin/tvguard-agent"));
    }
    @Test public void publicTargetsAndRedirectorRejected() {
        assertFalse(BridgeProtocol.validEndpoint("https://192.168.101.2/cgi-bin/tvguard-agent"));
        assertFalse(BridgeProtocol.validEndpoint("http://8.8.8.8/cgi-bin/tvguard-agent"));
        assertFalse(BridgeProtocol.validEndpoint("http://evil.test/cgi-bin/tvguard-agent"));
        assertFalse(BridgeProtocol.validEndpoint("http://192.168.101.2/cgi-bin/tvguard-agent?x=1"));
        assertFalse(BridgeProtocol.validEndpoint("http://127.0.0.1/cgi-bin/tvguard-agent"));
        assertFalse(BridgeProtocol.validEndpoint("http://192.168.101.2@8.8.8.8/cgi-bin/tvguard-agent"));
    }
    @Test public void pairingTokenFormatRequired() {
        assertTrue(BridgeProtocol.validKey(KEY));
        assertFalse(BridgeProtocol.validKey("password"));
        assertFalse(BridgeProtocol.validKey("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"));
    }
    @Test public void protocolMatchesN1WireSchema() {
        assertEquals("TVG2|" + KEY + "|5|com.gitvdemo.video|"
                + "com.gala.video.app.player.PlayerActivity|1|1|123456789|"
                + "allowed|usage_events|full_context\n",
                BridgeProtocol.body(KEY,5,"com.gitvdemo.video",
                        "com.gala.video.app.player.PlayerActivity",true,true,123456789L,
                        "allowed","usage_events","full_context"));
    }
    @Test public void tvg3AddsBoundedSamePackageActivityTrail() {
        ForegroundActivityHistory.Event[] timeline = new ForegroundActivityHistory.Event[] {
                new ForegroundActivityHistory.Event("com.gitvdemo.video",
                        "com.gala.video.plugincenter.component.InstrActivityProxy0", 40),
                new ForegroundActivityHistory.Event("com.gitvdemo.video",
                        "com.gala.video.app.player.PlayerActivity", 30),
                new ForegroundActivityHistory.Event("com.gitvdemo.video",
                        "com.gala.video.plugincenter.component.InstrActivityProxy0", 20),
                new ForegroundActivityHistory.Event("other.pkg",
                        "other.pkg.NoiseActivity", 10)
        };
        String trail = BridgeProtocol.activityTrail(timeline, "com.gitvdemo.video");
        assertEquals("com.gala.video.plugincenter.component.InstrActivityProxy0~"
                + "com.gala.video.app.player.PlayerActivity~"
                + "com.gala.video.plugincenter.component.InstrActivityProxy0", trail);
        String payload = BridgeProtocol.bodyV3(KEY, 6, "com.gitvdemo.video",
                "com.gala.video.plugincenter.component.InstrActivityProxy0",
                true, true, 123456790L, "allowed", "usage_events", "full_context", trail);
        assertTrue(payload.startsWith("TVG3|" + KEY + "|6|"));
        assertTrue(payload.contains("|allowed|usage_events|full_context|" + trail + "\n"));
        assertTrue(payload.length() < 768);
    }

    @Test public void tvg4AddsUiStructureDiagnosticsWithoutText() {
        String payload = BridgeProtocol.bodyV4(KEY, 7, "com.example.video",
                "com.example.video.PlayerActivity", true, true, 123456791L,
                "allowed", "usage_events", "full_context", "none",
                "com.example.video", 250L, 27, 12, 1, 6,
                "0123456789abcdef0123456789abcdef");
        assertTrue(payload.startsWith("TVG4|" + KEY + "|7|"));
        assertTrue(payload.contains("|com.example.video|250|27|12|1|6|"
                + "0123456789abcdef0123456789abcdef\n"));
        assertFalse(payload.contains("subtitle"));
        assertTrue(payload.length() < 1024);
    }

    @Test public void uiEvidenceMustMatchForegroundAndStayFresh() {
        String fp = "0123456789abcdef0123456789abcdef";
        assertTrue(BridgeProtocol.usableUi("com.example.video",
                "com.example.video", 19999L, fp));
        assertFalse(BridgeProtocol.usableUi("com.example.video",
                "com.example.other", 100L, fp));
        assertFalse(BridgeProtocol.usableUi("com.example.video",
                "com.example.video", 20001L, fp));
        assertFalse(BridgeProtocol.usableUi("com.example.video",
                "com.example.video", 100L, "none"));
    }

    @Test public void maliciousCharactersAndLongNamesSanitized() {
        StringBuilder sb = new StringBuilder();
        for(int i=0;i<999;i++) sb.append('A');
        String payload = BridgeProtocol.body(KEY,1,sb.toString(),sb.toString(),false,false,12,
                "default","usage_stats","package_only");
        assertTrue(payload.length() < 440);
        assertEquals("abcd", BridgeProtocol.sanitize("ab;c|d", 128));
    }
}
