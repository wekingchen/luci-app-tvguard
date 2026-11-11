#!/bin/sh
# Mocked daily digest; never contacts any real Bark endpoint.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/data-root"
printf 'PREV_DATE=2026-11-11\nPREV_WATCH_S=7265\nTODAY=2026-11-12\nUSED_S=7265\n' > "$TMP/data-root/state"

cat > "$TMP/bin/uci" <<'EOS'
#!/bin/sh
case "$3" in
    tvguard.main.bark_enabled) echo "${TVG_ENABLED:-1}" ;;
    tvguard.main.bark_server) echo "${TVG_SERVER:-https://api.day.app}" ;;
    tvguard.main.bark_key) echo "${TVG_KEY1:-abcDEF12345}" ;;
    tvguard.main.bark_key2) echo "${TVG_KEY2:-xyzSecond678}" ;;
    tvguard.main.child_name) echo '小明' ;;
    tvguard.main.bark_daily_time) echo "${TVG_WHEN:-00:05}" ;;
    *) exit 1 ;;
esac
EOS

cat > "$TMP/bin/date" <<'EOS'
#!/bin/sh
case "$1" in
    '+%H %M') echo "${TVG_CLOCK:-00 06}" ;;
    +%Y-%m-%d) echo '2026-11-12' ;;
    +%s) echo "${TVG_EPOCH:-1794441960}" ;;
    +%H:%M) echo '22:35' ;;
    *) exit 1 ;;
esac
EOS

cat > "$TMP/bin/curl" <<'EOS'
#!/bin/sh
printf 'attempt\n' >> "$TVG_PUSH_LOG"
printf '%s\n' "$*" >> "$TVG_ARGS_LOG"
case "${TVG_FAIL_KEY:-}" in
    '') : ;;
    *) case "$*" in *"device_key=$TVG_FAIL_KEY"*) echo '{"code":500}'; exit 0;; esac ;;
esac
echo '{"code":200,"message":"success"}'
EOS

cat > "$TMP/bin/logger" <<'EOS'
#!/bin/sh
exit 0
EOS

cat > "$TMP/data" <<'EOS'
#!/bin/sh
[ "$1" = root ] || exit 2
printf '%s\n' "$TVG_DATA_ROOT"
EOS

chmod +x "$TMP/bin/"* "$TMP/data"
export TVG_DATA_ROOT="$TMP/data-root" TVG_PUSH_LOG="$TMP/push" TVG_ARGS_LOG="$TMP/args"

python3 - "$ROOT/root/usr/libexec/tvguard-daily-report" "$TMP/worker" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,root=sys.argv[1:]
s=Path(src).read_text()
s=s.replace('PATH=/usr/sbin:/usr/bin:/sbin:/bin', 'PATH='+root+'/bin:/usr/sbin:/usr/bin:/sbin:/bin')
s=s.replace('DATA=/usr/libexec/tvguard-data', 'DATA='+root+'/data')
s=s.replace('RETRY=/var/run/tvguard-daily-report.retry', 'RETRY='+root+'/retry')
s=s.replace('mktemp /var/run/tvguard-bark.XXXXXX', 'mktemp '+root+'/reply.XXXXXX')
Path(dst).write_text(s)
PY
chmod 755 "$TMP/worker"

# Before schedule: no push.
export TVG_CLOCK='00 04'
sh "$TMP/worker" tick
[ ! -e "$TMP/push" ]

# Two configured IDs receive the same daily digest.
export TVG_CLOCK='00 06'
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 2 ]
grep -q 'device_key=abcDEF12345' "$TMP/args"
grep -q 'device_key=xyzSecond678' "$TMP/args"
grep -q '11月11日' "$TMP/args"
grep -q '小明全天累计看了约2小时1分钟电视' "$TMP/args"
[ "$(cat "$TMP/data-root/daily-report.sent")" = '2026-11-11' ]
[ "$(cat "$TMP/data-root/daily-report.sent.1")" = '2026-11-11' ]
[ "$(cat "$TMP/data-root/daily-report.sent.2")" = '2026-11-11' ]
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 2 ]

# Partial failure: successful recipient is remembered; retry sends only failed device.
rm -f "$TMP/data-root/daily-report.sent" "$TMP/data-root/daily-report.sent.1" "$TMP/data-root/daily-report.sent.2" "$TMP/retry"
: > "$TMP/push"
: > "$TMP/args"
export TVG_FAIL_KEY=xyzSecond678 TVG_EPOCH=1794441960
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 2 ]
[ "$(cat "$TMP/data-root/daily-report.sent.1")" = '2026-11-11' ]
[ ! -e "$TMP/data-root/daily-report.sent.2" ]
[ ! -e "$TMP/data-root/daily-report.sent" ]
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 2 ]
export TVG_FAIL_KEY= TVG_EPOCH=1794442261
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 3 ]
[ "$(grep -c 'device_key=abcDEF12345' "$TMP/args")" -eq 1 ]
[ "$(grep -c 'device_key=xyzSecond678' "$TMP/args")" -eq 2 ]
[ "$(cat "$TMP/data-root/daily-report.sent")" = '2026-11-11' ]

# Legacy one-ID config remains valid.
rm -f "$TMP/data-root/daily-report.sent" "$TMP/data-root/daily-report.sent.1" "$TMP/data-root/daily-report.sent.2" "$TMP/retry"
: > "$TMP/push"
: > "$TMP/args"
export TVG_KEY2=''
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]
grep -q 'device_key=abcDEF12345' "$TMP/args"
[ ! -e "$TMP/data-root/daily-report.sent.2" ]

# Same key in both slots is automatically de-duplicated.
rm -f "$TMP/data-root/daily-report.sent" "$TMP/data-root/daily-report.sent.1" "$TMP/data-root/daily-report.sent.2" "$TMP/retry"
: > "$TMP/push"
export TVG_KEY2=abcDEF12345
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]

# Disabled or malformed config remains silent on scheduled tick.
rm -f "$TMP/data-root/daily-report.sent" "$TMP/data-root/daily-report.sent.1" "$TMP/data-root/daily-report.sent.2" "$TMP/retry"
export TVG_ENABLED=0 TVG_KEY2=xyzSecond678
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]
export TVG_ENABLED=1 TVG_SERVER='https://api.day.app/extra/path'
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]
export TVG_SERVER='https://api.day.app' TVG_KEY2='bad/key'
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]

# A day with no child-mode watching must remain completely silent.
export TVG_KEY2=xyzSecond678 TVG_ENABLED=1
printf 'PREV_DATE=2026-11-11\nPREV_WATCH_S=0\nTODAY=2026-11-12\nUSED_S=7265\n' > "$TMP/data-root/state"
rm -f "$TMP/data-root/daily-report.sent" "$TMP/data-root/daily-report.sent.1" "$TMP/data-root/daily-report.sent.2" "$TMP/retry"
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]
[ ! -e "$TMP/data-root/daily-report.sent" ]

# Manual test sends to all configured devices and never poisons daily markers.
export TVG_ENABLED=0 TVG_CLOCK='00 01' TVG_KEY2=xyzSecond678
sh "$TMP/worker" test > "$TMP/test-result"
[ "$(wc -l < "$TMP/push")" -eq 3 ]
grep -q '小明的电视观看小结（测试）' "$TMP/args"
grep -q '截至11月12日 22:35' "$TMP/args"
grep -q '在儿童模式下累计看了约2小时1分钟电视' "$TMP/args"
grep -q '已发送到 2 台设备' "$TMP/test-result"
[ ! -e "$TMP/data-root/daily-report.sent" ]

# Zero usage refuses manual test before any push.
sed -i 's/^USED_S=7265$/USED_S=0/' "$TMP/data-root/state"
if sh "$TMP/worker" test > "$TMP/test-result" 2> "$TMP/test-error"; then
    echo "FAIL: zero child usage sent a Bark test" >&2
    exit 1
fi
[ "$(wc -l < "$TMP/push")" -eq 3 ]
grep -q '没有儿童模式下的观看记录' "$TMP/test-error"

# Manual test attempts both IDs, but reports partial failure accurately.
sed -i 's/^USED_S=0$/USED_S=3600/' "$TMP/data-root/state"
export TVG_FAIL_KEY=xyzSecond678
if sh "$TMP/worker" test > "$TMP/test-result" 2> "$TMP/test-error"; then
    echo "FAIL: partial Bark test reported full success" >&2
    exit 1
fi
grep -q '成功 1 台，失败 1 台' "$TMP/test-error"
[ ! -e "$TMP/data-root/daily-report.sent" ]

# Invalid second ID blocks whole manual test before any send.
export TVG_FAIL_KEY= TVG_KEY2='bad/key'
before="$(wc -l < "$TMP/push")"
if sh "$TMP/worker" test > "$TMP/test-result" 2> "$TMP/test-error"; then
    echo 'FAIL: malformed second device key was silently accepted' >&2
    exit 1
fi
grep -q '推送 ID 2 格式不正确' "$TMP/test-error"
[ "$(wc -l < "$TMP/push")" -eq "$before" ]

echo 'PASS: Bark dual-recipient delivery, per-device retry, zero suppression, manual test and validation'
