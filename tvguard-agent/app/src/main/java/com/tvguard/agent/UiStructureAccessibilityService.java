package com.tvguard.agent;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.view.accessibility.AccessibilityEvent;
import android.os.Handler;
import android.view.accessibility.AccessibilityNodeInfo;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * Optional, volatile UI-structure observer.
 * Never reads text/content-description and never writes UI data to disk.
 */
public final class UiStructureAccessibilityService extends AccessibilityService {
    private static final int MAX_NODES = 96;
    private static final int MAX_DEPTH = 10;
    private static final long REFRESH_INTERVAL_MS = 5000L;
    private static volatile Snapshot latest = Snapshot.empty();
    private static volatile boolean connected;
    private final Handler refreshHandler = new Handler();
    private final Runnable refreshTask = new Runnable() {
        @Override public void run() {
            if (!connected) return;
            captureCurrent();
            refreshHandler.postDelayed(this, REFRESH_INTERVAL_MS);
        }
    };

    public static final class Snapshot {
        public final long sampledMs;
        public final String packageName;
        public final int nodeCount;
        public final int clickableCount;
        public final int focusedCount;
        public final int viewIdCount;
        public final String fingerprint;

        Snapshot(long sampledMs, String packageName, int nodeCount,
                 int clickableCount, int focusedCount, int viewIdCount,
                 String fingerprint) {
            this.sampledMs = sampledMs;
            this.packageName = packageName == null ? "" : packageName;
            this.nodeCount = nodeCount;
            this.clickableCount = clickableCount;
            this.focusedCount = focusedCount;
            this.viewIdCount = viewIdCount;
            this.fingerprint = fingerprint == null ? "none" : fingerprint;
        }

        static Snapshot empty() {
            return new Snapshot(0L, "", 0, 0, 0, 0, "none");
        }
    }

    private static final class Accumulator {
        final MessageDigest digest;
        int nodes;
        int clickable;
        int focused;
        int ids;

        Accumulator(MessageDigest digest) {
            this.digest = digest;
        }
    }

    public static Snapshot snapshot() {
        return latest;
    }

    public static boolean isConnected() {
        return connected;
    }

    @Override
    protected void onServiceConnected() {
        connected = true;
        AccessibilityRecovery.onConnected(this);
        refreshHandler.removeCallbacks(refreshTask);
        captureCurrent();
        refreshHandler.postDelayed(refreshTask, REFRESH_INTERVAL_MS);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        captureCurrent();
    }

    @Override
    public void onInterrupt() {
        // No action. This observer has no queue and no local persistence.
    }

    @Override
    public boolean onUnbind(Intent intent) {
        connected = false;
        AccessibilityRecovery.onDisconnected();
        refreshHandler.removeCallbacks(refreshTask);
        latest = Snapshot.empty();
        return super.onUnbind(intent);
    }

    @Override
    public void onDestroy() {
        connected = false;
        AccessibilityRecovery.onDisconnected();
        refreshHandler.removeCallbacks(refreshTask);
        latest = Snapshot.empty();
        super.onDestroy();
    }

    private void captureCurrent() {
        AccessibilityNodeInfo root = null;
        try {
            root = getRootInActiveWindow();
            if (root == null) return;
            CharSequence pkgValue = root.getPackageName();
            String pkg = pkgValue == null ? "" : pkgValue.toString();
            if (pkg.length() == 0 || pkg.equals(getPackageName())) return;

            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            Accumulator a = new Accumulator(digest);
            walk(root, 0, a);
            latest = new Snapshot(System.currentTimeMillis(), pkg, a.nodes,
                    a.clickable, a.focused, a.ids, shortHex(digest.digest()));
        } catch (RuntimeException ignored) {
            // Vendor accessibility implementations can throw while a window is
            // changing. Keep the previous bounded RAM snapshot instead.
        } catch (NoSuchAlgorithmException impossible) {
            latest = Snapshot.empty();
        } finally {
            if (root != null) root.recycle();
        }
    }

    private void walk(AccessibilityNodeInfo node, int depth, Accumulator a) {
        if (node == null || depth > MAX_DEPTH || a.nodes >= MAX_NODES) return;
        a.nodes++;
        if (node.isClickable()) a.clickable++;
        if (node.isFocused()) a.focused++;

        String id = "";
        try {
            String raw = node.getViewIdResourceName();
            if (raw != null) id = raw;
        } catch (RuntimeException ignored) {
            id = "";
        }
        if (id.length() != 0) a.ids++;

        String cls = node.getClassName() == null ? "" : node.getClassName().toString();
        int bits = (node.isClickable() ? 1 : 0)
                | (node.isFocusable() ? 2 : 0)
                | (node.isFocused() ? 4 : 0)
                | (node.isSelected() ? 8 : 0)
                | (node.isEnabled() ? 16 : 0);
        update(a.digest, depth + "|" + cls + "|" + id + "|" + bits + ";");

        int children = Math.min(node.getChildCount(), MAX_NODES - a.nodes);
        for (int i = 0; i < children && a.nodes < MAX_NODES; i++) {
            AccessibilityNodeInfo child = null;
            try {
                child = node.getChild(i);
                if (child != null) walk(child, depth + 1, a);
            } catch (RuntimeException ignored) {
                // Ignore one malformed vendor node and continue the bounded walk.
            } finally {
                if (child != null) child.recycle();
            }
        }
    }

    private static void update(MessageDigest digest, String value) {
        byte[] bytes;
        try {
            bytes = value.getBytes("UTF-8");
        } catch (java.io.UnsupportedEncodingException impossible) {
            return;
        }
        digest.update(bytes);
    }

    private static String shortHex(byte[] digest) {
        StringBuilder out = new StringBuilder();
        int limit = Math.min(16, digest.length);
        for (int i = 0; i < limit; i++) {
            int value = digest[i] & 0xff;
            if (value < 16) out.append('0');
            out.append(Integer.toHexString(value));
        }
        return out.length() == 0 ? "none" : out.toString();
    }
}
