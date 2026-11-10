package com.tvguard.agent;

import android.content.Context;
import android.app.Activity;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import android.os.SystemClock;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.Proxy;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** Latest-state-only HTTP publisher; bounded timeouts, no logs or disk queue. */
final class BridgeClient {
    private static final String PREF = "bridge";
    static final String DEFAULT_ENDPOINT = "http://192.168.101.99/cgi-bin/tvguard-agent";
    private static volatile String state = "未配对";
    private static volatile long ackAt;
    private static long sentElapsed;
    private static long sequence;

    private BridgeClient() { }

    static String state() { return state; }
    static long ackAt() { return ackAt; }

    static String endpoint(Context ctx) {
        return ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("endpoint", DEFAULT_ENDPOINT);
    }
    static String token(Context ctx) {
        return ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("token", "");
    }

    interface PairingCallback {
        void onResult(boolean success, String message);
    }

    // Changing N1 address also clears the old secret to avoid accidentally
    // sending a token to a different host; only writes on explicit user click.
    static boolean saveAddress(Context ctx, String endpoint) {
        if (!BridgeProtocol.validEndpoint(endpoint)) return false;
        String cleaned = endpoint.trim();
        String old = endpoint(ctx);
        if (cleaned.equals(old)) return true;
        boolean saved = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
                .putString("endpoint", cleaned).remove("token").commit();
        if (saved) { state = "N1 地址已更改，请重新自动配对"; ackAt = 0; }
        return saved;
    }

    // Optional one-tap bootstrap. The N1 administrator must explicitly open
    // a 120s one-use window. Pairing key is NEVER embedded in APK.
    // Network work runs outside Android UI thread, with strict timeouts.
    static void autoPair(final Activity activity, final PairingCallback callback) {
        final String address = endpoint(activity);
        if (!BridgeProtocol.validEndpoint(address)) {
            callback.onResult(false, "N1 地址无效，请先修改地址");
            return;
        }
        state = "正在请求 N1 配对";
        Thread thread = new Thread(new Runnable() {
            @Override public void run() {
                boolean ok = false;
                String message = "无法配对，请确认 N1 已开启120秒配对窗口";
                HttpURLConnection connection = null;
                try {
                    connection = (HttpURLConnection) new URL(address)
                            .openConnection(Proxy.NO_PROXY);
                    connection.setRequestMethod("POST");
                    connection.setInstanceFollowRedirects(false);
                    connection.setConnectTimeout(1800);
                    connection.setReadTimeout(1800);
                    connection.setUseCaches(false);
                    connection.setRequestProperty("Content-Type", "text/plain; charset=US-ASCII");
                    connection.setDoOutput(true);
                    byte[] request = "PAIR1\n".getBytes(StandardCharsets.US_ASCII);
                    connection.setFixedLengthStreamingMode(request.length);
                    OutputStream output = connection.getOutputStream();
                    try {
                        output.write(request);
                        output.flush();
                    } finally {
                        output.close();
                    }
                    int status = connection.getResponseCode();
                    if (status == 200) {
                        BufferedReader reader = new BufferedReader(new InputStreamReader(
                                connection.getInputStream(), StandardCharsets.US_ASCII));
                        String response;
                        try { response = reader.readLine(); }
                        finally { reader.close(); }
                        if (response != null && response.startsWith("TOKEN1|")) {
                            String received = response.substring(7);
                            if (BridgeProtocol.validKey(received)) {
                                ok = savePair(activity, address, received);
                                message = ok ? "配对成功！监测开启后自动连接 N1" :
                                        "配对成功但无法保存配置";
                            }
                        }
                    } else {
                        message = "N1 未开放配对窗口（HTTP " + status + "）";
                    }
                } catch (Exception ignored) {
                    message = "无法连接 N1，请检查 N1 IP、网络与 CGI";
                } finally {
                    if (connection != null) connection.disconnect();
                }
                final boolean result = ok;
                final String note = message;
                if (!result) state = note;
                activity.runOnUiThread(new Runnable() {
                    @Override public void run() { callback.onResult(result, note); }
                });
            }
        }, "tvguard-pair");
        thread.setDaemon(true);
        thread.start();
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
