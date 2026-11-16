package com.tvguard.agent;

import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.SystemClock;
import android.provider.Settings;

/**
 * Bounded AccessibilityService health/recovery helper.
 *
 * No logs, history, files, database, timers or queues. The only persistent bit
 * records that this device successfully connected TVGuard accessibility once,
 * so optional WRITE_SECURE_SETTINGS recovery cannot silently opt a new user in.
 */
final class AccessibilityRecovery {
    private static final String PREFS = "control";
    private static final String KEY_MANAGED = "ui_recovery_managed";
    private static long unboundSinceElapsed;
    private static long lastNudgeElapsed;
    private static String lastAction = "none";

    private AccessibilityRecovery() { }

    static synchronized void onConnected(Context context) {
        unboundSinceElapsed = 0L;
        lastNudgeElapsed = 0L;
        lastAction = "connected";
        if (isConfigured(context) && !isManaged(context)) {
            SharedPreferences.Editor editor = context
                    .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit().putBoolean(KEY_MANAGED, true);
            editor.commit(); // One tiny bounded config write on first successful opt-in.
        }
    }

    static synchronized void onDisconnected() {
        if (unboundSinceElapsed == 0L) {
            unboundSinceElapsed = SystemClock.elapsedRealtime();
        }
        lastAction = "disconnected";
    }

    static synchronized String reconcile(Context context) {
        boolean monitorEnabled = MonitorService.isEnabled(context);
        boolean globalEnabled = isGlobalEnabled(context);
        boolean configured = isConfigured(context);
        boolean connected = UiStructureAccessibilityService.isConnected();
        boolean managed = isManaged(context);
        boolean canWrite = hasWriteSecureSettings(context);
        long now = SystemClock.elapsedRealtime();

        if (connected && globalEnabled && configured) {
            onConnected(context);
            return "connected";
        }
        if (!monitorEnabled) {
            unboundSinceElapsed = 0L;
            lastAction = "monitor_off";
            return lastAction;
        }
        if (unboundSinceElapsed == 0L) {
            unboundSinceElapsed = now;
        }
        long unboundFor = Math.max(0L, now - unboundSinceElapsed);
        long sinceNudge = lastNudgeElapsed == 0L
                ? Long.MAX_VALUE : Math.max(0L, now - lastNudgeElapsed);

        int decision = AccessibilityRecoveryPolicy.decide(
                monitorEnabled, globalEnabled, configured, connected,
                managed, canWrite, unboundFor, sinceNudge);
        if (decision == AccessibilityRecoveryPolicy.REPAIR_SECURE_SETTINGS) {
            if (repairSecureSettings(context, globalEnabled, configured)) {
                lastNudgeElapsed = now;
                lastAction = "secure_settings_repaired";
                return lastAction;
            }
            lastAction = "secure_repair_failed";
            return lastAction;
        }
        if (decision == AccessibilityRecoveryPolicy.NUDGE) {
            lastNudgeElapsed = now;
            lastAction = nudgeFramework(context) ? "framework_nudged" : "nudge_failed";
            return lastAction;
        }

        if (!globalEnabled) lastAction = "global_disabled";
        else if (!configured) lastAction = "authorization_missing";
        else lastAction = "configured_waiting_bind";
        return lastAction;
    }

    static synchronized String health(Context context) {
        if (!MonitorService.isEnabled(context)) return "monitor_off";
        // Settings truth must be checked before the binder flag. Xiaomi Android
        // 6 may keep a stale service binding alive after the global switch or
        // authorization entry has already been removed.
        if (!isGlobalEnabled(context)) return "global_disabled";
        if (!isConfigured(context)) return "authorization_missing";
        if (UiStructureAccessibilityService.isConnected()) return "connected";
        return "configured_waiting_bind";
    }

    static synchronized String lastAction() {
        return lastAction;
    }

    static boolean isManaged(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_MANAGED, false);
    }

    static boolean hasWriteSecureSettings(Context context) {
        return context.checkCallingOrSelfPermission(
                "android.permission.WRITE_SECURE_SETTINGS")
                == PackageManager.PERMISSION_GRANTED;
    }

    static boolean isGlobalEnabled(Context context) {
        try {
            return Settings.Secure.getInt(context.getContentResolver(),
                    Settings.Secure.ACCESSIBILITY_ENABLED, 0) == 1;
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    static boolean isConfigured(Context context) {
        String raw;
        try {
            raw = Settings.Secure.getString(context.getContentResolver(),
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        } catch (RuntimeException ignored) {
            return false;
        }
        if (raw == null || raw.length() == 0) return false;
        ComponentName expected = component(context);
        String[] parts = raw.split(":");
        for (String part : parts) {
            ComponentName found = ComponentName.unflattenFromString(part);
            if (expected.equals(found)) return true;
        }
        return false;
    }

    private static boolean repairSecureSettings(Context context,
                                                boolean globalEnabled,
                                                boolean configured) {
        if (!hasWriteSecureSettings(context) || !isManaged(context)) return false;
        ContentResolver resolver = context.getContentResolver();
        try {
            if (!configured) {
                String current = Settings.Secure.getString(resolver,
                        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
                String self = component(context).flattenToString();
                String repaired = appendServicePreservingExisting(current, self);
                if (!Settings.Secure.putString(resolver,
                        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, repaired)) {
                    return false;
                }
            }
            if (!globalEnabled && !Settings.Secure.putInt(resolver,
                    Settings.Secure.ACCESSIBILITY_ENABLED, 1)) {
                return false;
            }
            return nudgeFramework(context);
        } catch (SecurityException denied) {
            return false;
        } catch (RuntimeException failure) {
            return false;
        }
    }

    private static boolean nudgeFramework(Context context) {
        ContentResolver resolver = context.getContentResolver();
        try {
            // Configured-but-unbound recovery must remain write-free. Notify the
            // vendor framework observers only; do not repeatedly rewrite the
            // SettingsProvider database on this storage-constrained TV.
            //
            // Actual Settings.Secure writes are reserved for the much narrower
            // repairSecureSettings() path where prior opt-in is proven and the
            // authorization/global switch is genuinely missing.
            Uri services = Settings.Secure.getUriFor(
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            Uri enabled = Settings.Secure.getUriFor(
                    Settings.Secure.ACCESSIBILITY_ENABLED);
            resolver.notifyChange(services, null);
            resolver.notifyChange(enabled, null);
            return true;
        } catch (SecurityException denied) {
            return false;
        } catch (RuntimeException failure) {
            return false;
        }
    }

    static String appendServicePreservingExisting(String current, String self) {
        String safeCurrent = current == null ? "" : current.trim();
        if (safeCurrent.length() == 0) return self;
        String[] parts = safeCurrent.split(":");
        ComponentName expected = ComponentName.unflattenFromString(self);
        for (String part : parts) {
            ComponentName found = ComponentName.unflattenFromString(part);
            if (expected != null && expected.equals(found)) return safeCurrent;
        }
        return safeCurrent + ":" + self;
    }

    private static ComponentName component(Context context) {
        return new ComponentName(context, UiStructureAccessibilityService.class);
    }
}
