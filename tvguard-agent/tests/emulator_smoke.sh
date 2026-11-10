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

# This is a touch-screen phone emulator, not a TV remote. Find the actual
# button bounds in UIAutomator instead of relying on DPAD key focus.
adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-window.xml
coords="$(python3 - <<'PY'
import re
import xml.etree.ElementTree as ET
root=ET.parse('/tmp/tvguard-window.xml').getroot()
for node in root.iter('node'):
    if node.attrib.get('text') == '开始监测':
        b=node.attrib.get('bounds','')
        nums=list(map(int,re.findall(r'\d+',b)))
        if len(nums)==4:
            print((nums[0]+nums[2])//2, (nums[1]+nums[3])//2)
            break
PY
)"
if [ -z "$coords" ]; then
  echo "[smoke] START BUTTON NOT FOUND"
  head -c 4500 /tmp/tvguard-window.xml || :
  exit 1
fi
adb shell input tap $coords
sleep 9
if ! adb shell dumpsys activity services "$PKG" | grep -q 'MonitorService'; then
  echo "[smoke] MonitorService not running after button tap"
  adb shell dumpsys activity services "$PKG" | tail -70
  adb shell run-as "$PKG" cat shared_prefs/control.xml || :
  exit 1
fi
echo "[smoke] service active PASS"

adb shell am start -W -a android.settings.SETTINGS >/dev/null
sleep 8
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 3
adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-window.xml
if ! grep -q 'com.android.settings' /tmp/tvguard-window.xml; then
  echo "[smoke] foreground usage state not displayed"
  head -c 4000 /tmp/tvguard-window.xml || :
  exit 1
fi
echo "[smoke] foreground usage event PASS"

before="$(adb shell run-as "$PKG" du -sk . | head -1 | tr -d '\r' | awk '{print $1}')"
sleep 12
after="$(adb shell run-as "$PKG" du -sk . | head -1 | tr -d '\r' | awk '{print $1}')"
test "$before" = "$after"
echo "[smoke] no ongoing private disk growth PASS ($after KiB)"

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
