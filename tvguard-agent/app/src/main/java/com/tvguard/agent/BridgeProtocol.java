package com.tvguard.agent;

import java.net.URI;

/** Wire schema shared by phone-side publisher and N1 CGI; no Android deps. */
final class BridgeProtocol {
    private BridgeProtocol() { }

    static boolean validEndpoint(String raw) {
        if (raw == null || raw.length() > 120) return false;
        try {
            URI u = new URI(raw.trim());
            if (!"http".equals(u.getScheme()) || u.getHost() == null
                    || u.getUserInfo() != null || u.getRawQuery() != null
                    || u.getRawFragment() != null || u.getPort() == 0
                    || u.getPort() > 65535
                    || !"/cgi-bin/tvguard-agent".equals(u.getPath())) return false;
            return privateIPv4(u.getHost());
        } catch (Exception ignored) { return false; }
    }

    private static boolean privateIPv4(String host) {
        if (!host.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}")) return false;
        String[] parts = host.split("\\.");
        int[] n = new int[4];
        for (int i = 0; i < 4; i++) {
            n[i] = Integer.parseInt(parts[i]);
            if (n[i] > 255) return false;
        }
        return n[0] == 10 || (n[0] == 172 && n[1] >= 16 && n[1] <= 31)
                || (n[0] == 192 && n[1] == 168);
    }

    static boolean validKey(String key) {
        return key != null && key.matches("[0-9a-f]{32}");
    }

    static String sanitize(String value, int limit) {
        if (value == null || value.length() == 0) return "unknown";
        StringBuilder sb = new StringBuilder();
        for (int i=0; i<value.length() && sb.length()<limit; i++) {
            char c = value.charAt(i);
            if (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
                    || c >= '0' && c <= '9' || c == '.' || c == '_' || c == '$')
                sb.append(c);
        }
        return sb.length()==0 ? "unknown" : sb.toString();
    }

    static String body(String key, long seq, String pkg, String cls,
                       boolean audio, boolean screen, long wallTimeMs) {
        if (!validKey(key)) throw new IllegalArgumentException("Invalid key");
        return "TVG1|" + key + "|" + seq + "|" + sanitize(pkg, 128) + "|"
                + sanitize(cls, 160) + "|" + (audio ? 1 : 0) + "|"
                + (screen ? 1 : 0) + "|" + wallTimeMs + "\n";
    }
}
