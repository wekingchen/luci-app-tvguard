#!/usr/bin/env bash
set -euo pipefail
APK=tvguard-agent/app/build/outputs/apk/debug/app-debug.apk
PKG=com.tvguard.agent
adb install -r "$APK"
adb shell am start -W -n "$PKG/.MainActivity" | grep -E 'Status: ok|Complete'
echo "[smoke] boot/launch PASS"
# am start -W can finish BEFORE the Android 6 window receives input focus.
# A DPAD_DOWN injected during transition gets dropped, while the next OK
# arrives after focus and incorrectly clicks "Start monitoring".
# Wait for our window to own the input focus before sending remote keys.
for i in $(seq 1 15); do
  if adb shell dumpsys window windows | grep -q 'mCurrentFocus=.*com.tvguard.agent'; then
    break
  fi
  sleep 1
done
sleep 2
# The Nexus 5 emulator is a TOUCH device; DPAD_DOWN has been observed to be
# swallowed by its ScrollView even when TV navigation handlers exist.
# What matters for first-boot pairing is the DEFAULT focused action: press OK
# once, without any navigation or TV IME, and never toggle monitoring by mistake.
adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-initial.xml
python3 - <<'PY'
import xml.etree.ElementTree as ET
root=ET.parse('/tmp/tvguard-initial.xml').getroot()
focused = [n.attrib.get('text','') for n in root.iter('node')
           if n.attrib.get('focused') == 'true']
assert any('自动配对 N1' in t for t in focused), focused
PY
echo "[smoke] one-tap pairing preselected PASS"
adb shell input keyevent 23
sleep 3
adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-after-ok.xml
grep -q 'N1：' /tmp/tvguard-after-ok.xml
echo "[smoke] one-tap pairing action without TV keyboard PASS"

# Verify numeric keypad using a direct UI click in the touch emulator.
# D-pad navigation must still be checked on the real Android TV.
python3 - <<'PY' > /tmp/tvguard-keypad-tap
import re
import xml.etree.ElementTree as ET
root=ET.parse('/tmp/tvguard-after-ok.xml').getroot()
for n in root.iter('node'):
    if n.attrib.get('text','').startswith('修改 N1 地址'):
        bounds=list(map(int,re.findall(r'\d+',n.attrib.get('bounds',''))))
        if len(bounds)==4:
            print((bounds[0]+bounds[2])//2, (bounds[1]+bounds[3])//2)
            break
PY
coords="$(cat /tmp/tvguard-keypad-tap)"
test -n "$coords"
adb shell input tap $coords
sleep 1
adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-address-dialog.xml
if ! grep -q '清空' /tmp/tvguard-address-dialog.xml; then
  echo "[smoke] numeric IPv4 keypad not visible"
  head -c 4500 /tmp/tvguard-address-dialog.xml || :
  exit 1
fi
echo "[smoke] no-IME numeric IPv4 keypad available PASS"
adb shell input keyevent 4
sleep 1

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
# Foreground service must register an ongoing system notification.
if ! adb shell dumpsys notification --noredact | grep -q "$PKG"; then
  echo "[smoke] notification not registered"
  exit 1
fi
echo "[smoke] visible foreground notification PASS"

adb shell am start -W -a android.settings.SETTINGS >/dev/null
sleep 8
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 3
# New TV-only pairing controls occupy the top viewport. UsageStats evidence
# is BELOW the fold; UIAutomator only dumps visible nodes. Scroll deliberately
# before concluding the application did not record the Activity.
for i in 1 2 3 4 5; do
  adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
  adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-window.xml
  if grep -q 'com.android.settings' /tmp/tvguard-window.xml; then break; fi
  adb shell input swipe 1100 950 1100 250 450
  sleep 1
done
if ! grep -q 'com.android.settings' /tmp/tvguard-window.xml; then
  echo "[smoke] foreground usage state not displayed"
  head -c 4000 /tmp/tvguard-window.xml || :
  exit 1
fi
echo "[smoke] foreground usage event PASS"
# The pairing control is intentionally offscreen after scrolling to UsageStats.
# Its presence and initial OK handling were confirmed before this step.
echo "[smoke] N1 pairing UI PASS (verified before scrolling)"

# Reproduce real MiTV flow: Settings (stand-in for other app) -> HOME ->
# reopen Agent. The last non-launcher must remain Settings, not the home app.
adb shell am start -W -a android.settings.SETTINGS >/dev/null
sleep 4
adb shell input keyevent 3
sleep 4
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 5
for i in 1 2 3 4 5; do
  adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
  adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-window.xml
  if grep -q '【最近非桌面 App】' /tmp/tvguard-window.xml; then break; fi
  adb shell input swipe 1100 950 1100 250 450
  sleep 1
done
python3 - <<'PY'
import xml.etree.ElementTree as ET
root = ET.parse('/tmp/tvguard-window.xml').getroot()
texts = [node.attrib.get("text", "") for node in root.iter("node")]
assert any("【最近非桌面 App】" in t and "com.android.settings" in t for t in texts), texts
PY
echo "[smoke] home-navigation does not erase previous non-launcher app PASS"

before="$(adb shell run-as "$PKG" du -sk . | head -1 | tr -d '\r' | awk '{print $1}')"
sleep 12
after="$(adb shell run-as "$PKG" du -sk . | head -1 | tr -d '\r' | awk '{print $1}')"
test "$before" = "$after"
echo "[smoke] no ongoing private disk growth PASS ($after KiB)"

# Reproduce MiTV screenshot: enabled flag survives process death, Activity
# reopened from launcher; a previously dead service must be restarted.
adb shell am force-stop "$PKG"
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 8
if ! adb shell dumpsys activity services "$PKG" | grep -q 'MonitorService'; then
  echo "[smoke] FAILED reopening UI after process termination"
  exit 1
fi
for i in 1 2 3 4 5; do
  adb shell uiautomator dump /sdcard/tvguard-window.xml >/dev/null
  adb exec-out cat /sdcard/tvguard-window.xml > /tmp/tvguard-window.xml
  if grep -q '采样正常' /tmp/tvguard-window.xml; then break; fi
  adb shell input swipe 1100 950 1100 250 450
  sleep 1
done
if ! grep -q '采样正常' /tmp/tvguard-window.xml; then
  echo "[smoke] sample not recovered after reopening UI"
  head -c 4500 /tmp/tvguard-window.xml || :
  exit 1
fi
echo "[smoke] recovered user-enabled service after force stop PASS"

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
