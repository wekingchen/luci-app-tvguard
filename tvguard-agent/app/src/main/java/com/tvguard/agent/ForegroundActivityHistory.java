package com.tvguard.agent;

import java.util.ArrayDeque;
import java.util.Iterator;

/**
 * Generic foreground Activity history held strictly in bounded RAM.
 *
 * The Agent does not maintain a whitelist of "video apps". It only reports
 * foreground context. N1 learns whether a context is media from network
 * evidence and temporal fusion.
 */
final class ForegroundActivityHistory {
    static final int CAPACITY = 24;
    private final ArrayDeque<Event> recent = new ArrayDeque<Event>(CAPACITY);

    static final class Event {
        final String packageName;
        final String activityName;
        final long timeMs;

        Event(String packageName, String activityName, long timeMs) {
            this.packageName = shrink(packageName);
            this.activityName = shrink(activityName);
            this.timeMs = timeMs;
        }
    }

    void clear() {
        recent.clear();
    }

    int size() {
        return recent.size();
    }

    void recordForeground(String pkg, String activity, long timeMs, String ownPackage) {
        if (pkg == null || pkg.length() == 0 || pkg.equals(ownPackage) || timeMs <= 0L) {
            return;
        }
        Event last = recent.peekLast();
        String safeClass = shrink(activity);
        if (last != null && timeMs < last.timeMs) {
            return;
        }
        // queryEvents intentionally overlaps consecutive windows by one second.
        if (last != null && last.timeMs == timeMs
                && last.packageName.equals(pkg)
                && last.activityName.equals(safeClass)) {
            return;
        }
        if (recent.size() == CAPACITY) {
            recent.removeFirst();
        }
        recent.addLast(new Event(pkg, safeClass, timeMs));
    }

    Event lastNonLauncher() {
        Iterator<Event> it = recent.descendingIterator();
        while (it.hasNext()) {
            Event event = it.next();
            if (!isLauncherPackage(event.packageName)) return event;
        }
        return null;
    }

    Event[] lastEvents(int count) {
        int n = Math.min(Math.max(0, count), recent.size());
        Event[] result = new Event[n];
        int i = 0;
        Iterator<Event> it = recent.descendingIterator();
        while (it.hasNext() && i < n) {
            result[i++] = it.next();
        }
        return result;
    }

    static boolean isLauncherPackage(String pkg) {
        if (pkg == null) return false;
        return pkg.equals("com.mitv.tvhome")
                || pkg.equals("com.mitv.home")
                || pkg.equals("com.android.tvlauncher")
                || pkg.equals("com.google.android.tvlauncher")
                || pkg.equals("com.google.android.apps.tv.launcherx")
                || pkg.equals("com.android.launcher")
                || pkg.equals("com.android.launcher3")
                || pkg.equals("com.miui.tvhome");
    }

    private static String shrink(String value) {
        if (value == null) return "";
        return value.length() > 160 ? value.substring(0, 160) : value;
    }
}
