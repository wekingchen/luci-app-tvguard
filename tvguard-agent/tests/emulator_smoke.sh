#!/usr/bin/env bash
set -euo pipefail
APK=tvguard-agent/app/build/outputs/apk/debug/app-debug.apk
PKG=com.tvguard.agent
adb install -r "$APK"
adb shell am start -W -n "$PKG/.MainActivity" | grep -E 'Status: ok|Complete'
echo "[smoke] boot/launch PASS"
adb shell appops set "$PKG" GET_USAGE_STATS allow
adb shell appops get "$PKG" GET_USAGE_STATS | grep -q 'allow'
echo "[smoke] appops PASS"
# The Button is the only focusable view. Select with the TV remote keycode.
adb shell input keyevent 23
sleep 9
adb shell dumpsys activity services "$PKG" | grep -q 'MonitorService'
echo "[smoke] service active PASS"
# Switch to Settings; switch directly back so 'last other app' can be inspected.
adb shell am start -W -a android.settings.SETTINGS >/dev/null
sleep 8
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 3
adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
adb shell cat /sdcard/tvguard-window.xml | grep -q 'com.android.settings'
echo "[smoke] foreground usage event PASS"
# Verify sampling causes no app-owned files to grow.
before="$(adb shell run-as "$PKG" du -sk . | head -1 | tr -d '\r' | awk '{print $1}')"
sleep 12
after="$(adb shell run-as "$PKG" du -sk . | head -1 | tr -d '\r' | awk '{print $1}')"
test "$before" = "$after"
echo "[smoke] no ongoing private disk growth PASS ($after KiB)"
# Reboot: ADB resumes in emulator; BOOT_COMPLETED should restart the service.
adb reboot
adb wait-for-device
for i in $(seq 1 90); do
  [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break
  sleep 2
done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
adb shell appops get "$PKG" GET_USAGE_STATS | grep -q 'allow'
sleep 8
adb shell dumpsys activity services "$PKG" | grep -q 'MonitorService'
echo "[smoke] permission and service survive boot PASS"
