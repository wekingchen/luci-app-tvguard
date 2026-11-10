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
        assertEquals("TVG1|" + KEY + "|5|com.gitvdemo.video|"
                + "com.gala.video.app.player.PlayerActivity|1|1|123456789\n",
                BridgeProtocol.body(KEY,5,"com.gitvdemo.video",
                        "com.gala.video.app.player.PlayerActivity",true,true,123456789L));
    }
    @Test public void maliciousCharactersAndLongNamesSanitized() {
        StringBuilder sb = new StringBuilder();
        for(int i=0;i<999;i++) sb.append('A');
        String payload = BridgeProtocol.body(KEY,1,sb.toString(),sb.toString(),false,false,12);
        assertTrue(payload.length() < 440);
        assertEquals("abcd", BridgeProtocol.sanitize("ab;c|d", 128));
    }
}
