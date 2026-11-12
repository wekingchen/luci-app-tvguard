package com.tvguard.agent;

/** Pure Java event fold. No Android dependencies, network, file I/O or storage. */
final class ForegroundReducer {
    String currentPackage;
    String currentClass;
    String lastOtherPackage;
    String lastOtherClass;
    long changedMs;

    ForegroundReducer(String currentPackage, String currentClass,
                      String lastOtherPackage, String lastOtherClass, long changedMs) {
        this.currentPackage = clean(currentPackage);
        this.currentClass = clean(currentClass);
        this.lastOtherPackage = clean(lastOtherPackage);
        this.lastOtherClass = clean(lastOtherClass);
        this.changedMs = changedMs;
    }

    void foreground(String pkg, String className, long epochMs, String ownPackage) {
        if (pkg == null || pkg.length() == 0 || epochMs < changedMs) return;
        currentPackage = pkg;
        currentClass = clean(className);
        changedMs = epochMs;
        if (!pkg.equals(ownPackage)) {
            lastOtherPackage = pkg;
            lastOtherClass = currentClass;
        }
    }

    void background(String pkg, String className, long epochMs) {
        if (pkg == null || !pkg.equals(currentPackage) || epochMs < changedMs) return;
        // Android can emit the old Activity's BACKGROUND after the new Activity's
        // FOREGROUND, even inside one package. Don't erase the new Activity.
        if (className != null && className.length() > 0 && currentClass.length() > 0
                && !className.equals(currentClass)) return;
        currentPackage = "";
        currentClass = "";
        changedMs = epochMs;
    }

    private static String clean(String value) {
        return value == null ? "" : value;
    }
}
