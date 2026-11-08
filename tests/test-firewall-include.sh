#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
LOG="$TMP/log"
: > "$LOG"

cat > "$TMP/fw" <<'SH'
#!/bin/sh
printf 'fw %s\n' "$*" >> "$TVG_INCLUDE_TEST_LOG"
exit "${TVG_FW_EXIT:-0}"
SH
cat > "$TMP/logger" <<'SH'
#!/bin/sh
printf 'logger %s\n' "$*" >> "$TVG_INCLUDE_TEST_LOG"
exit 0
SH
chmod +x "$TMP/fw" "$TMP/logger"

python3 - "$ROOT/root/usr/libexec/tvguard-firewall-include" "$TMP/include" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst,tmp=sys.argv[1:]
s=Path(src).read_text()
s=s.replace("/usr/libexec/tvguard-fw", tmp+"/fw")
# Use a fixed logger path so PATH cannot mask behavior.
s=s.replace("logger -t tvguard", tmp+"/logger -t tvguard")
Path(dst).write_text(s)
PY
chmod +x "$TMP/include"
export TVG_INCLUDE_TEST_LOG="$LOG"

# Normal TVG sync succeeds and include succeeds.
export TVG_FW_EXIT=0
sh "$TMP/include"
grep -q '^fw sync$' "$LOG"
! grep -q '^logger ' "$LOG"

# A TVG failure is logged but MUST NOT propagate to firewall3/proxy reload.
: > "$LOG"
export TVG_FW_EXIT=7
sh "$TMP/include"
grep -q '^fw sync$' "$LOG"
grep -q '^logger -t tvguard isolated firewall sync failed;' "$LOG"

echo "PASS: TV Guard include cannot fail global firewall/proxy reload"
