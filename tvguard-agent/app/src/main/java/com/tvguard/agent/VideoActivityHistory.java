package com.tvguard.agent;

import java.util.ArrayDeque;
import java.util.Iterator;

/**
 * Foreground activity history held strictly in a bounded RAM ring.
 *
 * The launcher and Agent are excluded only when selecting the last meaningful
 * app. Their presence does not erase the earlier video/other-app activity.
 * No I/O, background tasks, disk cache or network permission.
 */
final class VideoActivityHistory {
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

    Event lastVideo() {
        Iterator<Event> it = recent.descendingIterator();
        while (it.hasNext()) {
            Event event = it.next();
            if (isVideoPackage(event.packageName)) return event;
        }
        return null;
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

    static boolean isVideoPackage(String pkg) {
        if (pkg == null) return false;
        return pkg.equals("com.gitvdemo.video")       // 银河奇异果
                || pkg.equals("com.ktcp.video")       // 云视听极光
                || pkg.equals("org.smarttube.stable") // SmartTube
                || pkg.equals("com.hunantv.license")  // 芒果TV
                || pkg.equals("com.iqiyi.tv")
                || pkg.equals("com.youku.tv")
                || pkg.equals("com.tencent.qqlivetv")
                || pkg.equals("com.bilibili.tv");
    }

    private static String shrink(String value) {
        if (value == null) return "";
        return value.length() > 160 ? value.substring(0, 160) : value;
    }
}
