package com.tvguard.agent;

import android.content.Context;
import android.os.SystemClock;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.Proxy;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** Latest-state-only HTTP publisher; bounded timeouts, no logs or disk queue. */
final class BridgeClient {
    private static final String PREF = "bridge";
    private static volatile String state = "未配对";
    private static volatile long ackAt;
    private static long sentElapsed;
    private static long sequence;

    private BridgeClient() { }

    static String state() { return state; }
    static long ackAt() { return ackAt; }

    static String endpoint(Context ctx) {
        return ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("endpoint", "");
    }
    static String token(Context ctx) {
        return ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("token", "");
    }

    static boolean savePair(Context ctx, String endpoint, String token) {
        if (endpoint == null || token == null) return false;
        endpoint = endpoint.trim();
        token = token.trim();
        if (!BridgeProtocol.validEndpoint(endpoint) || !BridgeProtocol.validKey(token)) return false;
        boolean saved = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
                .putString("endpoint", endpoint).putString("token", token).commit();
        if (saved) {
            state = "已配对，等待上报";
            sentElapsed = 0;
        }
        return saved;
    }

    static void maybeSend(Context ctx, String pkg, String cls,
                          boolean audio, boolean screen, long wallTimeMs) {
        long now = SystemClock.elapsedRealtime();
        if (sentElapsed != 0 && now >= sentElapsed && now - sentElapsed < 10000L) return;
        sentElapsed = now;
        String endpoint = endpoint(ctx), token = token(ctx);
        if (!BridgeProtocol.validEndpoint(endpoint) || !BridgeProtocol.validKey(token)) {
            state = "未配对"; return;
        }
        String body = BridgeProtocol.body(token, ++sequence, pkg, cls, audio, screen, wallTimeMs);
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(endpoint).openConnection(Proxy.NO_PROXY);
            conn.setRequestMethod("POST");
            conn.setInstanceFollowRedirects(false);
            conn.setConnectTimeout(1500);
            conn.setReadTimeout(1500);
            conn.setUseCaches(false);
            conn.setRequestProperty("Content-Type", "text/plain; charset=US-ASCII");
            conn.setDoOutput(true);
            byte[] data = body.getBytes(StandardCharsets.US_ASCII);
            conn.setFixedLengthStreamingMode(data.length);
            OutputStream output = conn.getOutputStream();
            try {
                output.write(data);
                output.flush();
            } finally {
                output.close();
            }
            int code = conn.getResponseCode();
            if (code == 200) {
                state = "N1 已接收";
                ackAt = System.currentTimeMillis();
            } else {
                state = "N1 拒绝（HTTP " + code + "）";
            }
        } catch (Exception ignored) {
            state = "N1 暂不可达（未缓存数据）";
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
}
