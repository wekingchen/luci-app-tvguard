#!/bin/sh
# Mocked daily digest; never contacts any real Bark endpoint.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/data-root"
printf 'PREV_DATE=2026-11-11\nPREV_WATCH_S=7265\n' > "$TMP/data-root/state"
cat > "$TMP/bin/uci" <<'EOS'
#!/bin/sh
case "$3" in
    tvguard.main.bark_enabled) echo "${TVG_ENABLED:-1}" ;;
    tvguard.main.bark_server) echo "${TVG_SERVER:-https://api.day.app}" ;;
    tvguard.main.bark_key) echo "${TVG_KEY:-abcDEF12345}" ;;
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
printf '%s\n' "$*" > "$TVG_ARGS_LOG"
if [ "${TVG_CURL_FAIL:-0}" = 1 ]; then
    echo '{"code":500}'
else
    echo '{"code":200,"message":"success"}'
fi
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
export TVG_CLOCK='00 04'
sh "$TMP/worker" tick
[ ! -e "$TMP/push" ]
export TVG_CLOCK='00 06'
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]
grep -q 'device_key=abcDEF12345' "$TMP/args"
grep -q '11月11日' "$TMP/args"
grep -q '小明全天累计看了约2小时1分钟电视' "$TMP/args"
! grep -q '家长模式不算在内' "$TMP/args"
! grep -q '含家长与儿童模式' "$TMP/args"
[ "$(cat "$TMP/data-root/daily-report.sent")" = '2026-11-11' ]
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 1 ]
# Failure does not claim delivery. Rapid repeated polls do not retry immediately.
rm -f "$TMP/data-root/daily-report.sent"
export TVG_CURL_FAIL=1
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 2 ]
[ ! -e "$TMP/data-root/daily-report.sent" ]
export TVG_CURL_FAIL=0
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 2 ]
export TVG_EPOCH=1794442261
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 3 ]
[ "$(cat "$TMP/data-root/daily-report.sent")" = '2026-11-11' ]
rm -f "$TMP/data-root/daily-report.sent"
export TVG_ENABLED=0
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 3 ]
export TVG_ENABLED=1 TVG_SERVER='https://api.day.app/extra/path'
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 3 ]
export TVG_SERVER='https://api.day.app' TVG_KEY='bad/key'
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 3 ]
# A day with no child-mode watching must remain completely silent.
export TVG_SERVER='https://api.day.app' TVG_KEY=abcDEF12345 TVG_ENABLED=1
printf 'PREV_DATE=2026-11-11\nPREV_WATCH_S=0\nTODAY=2026-11-12\nUSED_S=7265\n' > "$TMP/data-root/state"
rm -f "$TMP/data-root/daily-report.sent" "$TMP/retry"
sh "$TMP/worker" tick
[ "$(wc -l < "$TMP/push")" -eq 3 ]
[ ! -e "$TMP/data-root/daily-report.sent" ]

# Manual Bark test deliberately ignores the schedule/enabled flag. It reads
# today's child-only used seconds, not previous-day data, with a clear "as of".
export TVG_ENABLED=0 TVG_CLOCK='00 01'
sh "$TMP/worker" test > "$TMP/test-result"
[ "$(wc -l < "$TMP/push")" -eq 4 ]
grep -q '小明的电视观看小结（测试）' "$TMP/args"
grep -q '截至11月12日 22:35' "$TMP/args"
grep -q '在儿童模式下累计看了约2小时1分钟电视' "$TMP/args"
grep -q '测试推送已发送' "$TMP/test-result"
[ ! -e "$TMP/data-root/daily-report.sent" ]
# Repeated on-demand tests never poison the daily sent marker.
sh "$TMP/worker" test > "$TMP/test-result"
[ "$(wc -l < "$TMP/push")" -eq 5 ]
[ ! -e "$TMP/data-root/daily-report.sent" ]

# Zero usage must also refuse a manual test and tell the administrator why.
sed -i 's/^USED_S=7265$/USED_S=0/' "$TMP/data-root/state"
if sh "$TMP/worker" test > "$TMP/test-result" 2> "$TMP/test-error"; then
    echo "FAIL: zero child usage sent a Bark test" >&2
    exit 1
fi
[ "$(wc -l < "$TMP/push")" -eq 5 ]
grep -q '没有儿童模式下的观看记录' "$TMP/test-error"

# A rejected Bark response must NOT claim success in the settings UI.
sed -i 's/^USED_S=0$/USED_S=3600/' "$TMP/data-root/state"
export TVG_CURL_FAIL=1
if sh "$TMP/worker" test > "$TMP/test-result" 2> "$TMP/test-error"; then
    echo "FAIL: Bark test reported success for a failed response" >&2
    exit 1
fi
grep -q 'Bark 测试推送失败' "$TMP/test-error"
[ ! -e "$TMP/data-root/daily-report.sent" ]
echo 'PASS: concise Bark daily, zero suppression, latest test sample, retries and deduplication'
