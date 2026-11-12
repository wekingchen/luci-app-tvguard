package com.tvguard.agent;

import java.net.URI;

/** Wire schema shared by TV Agent publisher and N1 CGI; no Android deps. */
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

    static String activityTrail(ForegroundActivityHistory.Event[] events,
                                String currentPackage) {
        if (events == null || currentPackage == null || currentPackage.length() == 0) {
            return "none";
        }
        StringBuilder out = new StringBuilder();
        String previous = "";
        int kept = 0;
        for (ForegroundActivityHistory.Event event : events) {
            if (event == null || !currentPackage.equals(event.packageName)) continue;
            String cls = sanitize(event.activityName, 96);
            if ("unknown".equals(cls) || cls.equals(previous)) continue;
            int added = cls.length() + (out.length() == 0 ? 0 : 1);
            if (out.length() + added > 240) break;
            if (out.length() != 0) out.append('~');
            out.append(cls);
            previous = cls;
            kept++;
            if (kept >= 4) break;
        }
        return out.length() == 0 ? "none" : out.toString();
    }

    static String sanitizeTrail(String value) {
        if (value == null || value.length() == 0) return "none";
        StringBuilder sb = new StringBuilder();
        for (int i=0; i<value.length() && sb.length()<240; i++) {
            char c = value.charAt(i);
            if (c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
                    || c >= '0' && c <= '9' || c == '.' || c == '_'
                    || c == '
}
 || c == '~')
                sb.append(c);
        }
        return sb.length()==0 ? "none" : sb.toString();
    }

    static String body(String key, long seq, String pkg, String cls,
                       boolean audio, boolean screen, long wallTimeMs,
                       String usageAccess, String foregroundSource,
                       String foregroundStatus) {
        if (!validKey(key)) throw new IllegalArgumentException("Invalid key");
        return "TVG2|" + key + "|" + seq + "|" + sanitize(pkg, 128) + "|"
                + sanitize(cls, 160) + "|" + (audio ? 1 : 0) + "|"
                + (screen ? 1 : 0) + "|" + wallTimeMs + "|"
                + sanitize(usageAccess, 24) + "|"
                + sanitize(foregroundSource, 32) + "|"
                + sanitize(foregroundStatus, 48) + "\n";
    }

    static String bodyV3(String key, long seq, String pkg, String cls,
                         boolean audio, boolean screen, long wallTimeMs,
                         String usageAccess, String foregroundSource,
                         String foregroundStatus, String activityTrail) {
        if (!validKey(key)) throw new IllegalArgumentException("Invalid key");
        return "TVG3|" + key + "|" + seq + "|" + sanitize(pkg, 128) + "|"
                + sanitize(cls, 160) + "|" + (audio ? 1 : 0) + "|"
                + (screen ? 1 : 0) + "|" + wallTimeMs + "|"
                + sanitize(usageAccess, 24) + "|"
                + sanitize(foregroundSource, 32) + "|"
                + sanitize(foregroundStatus, 48) + "|"
                + sanitizeTrail(activityTrail) + "\n";
    }
}
