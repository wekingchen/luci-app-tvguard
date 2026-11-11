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
grep -q '2026-11-11' "$TMP/args"
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
echo 'PASS: previous-day Bark delivery, retry, deduplication, schedule and input guards'
