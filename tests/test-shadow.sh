#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
SRC="$ROOT/root/usr/libexec/tvguard-shadow"
DST="$TMP/tvguard-shadow"
CSV="$TMP/calibration-v3.csv"
python3 - "$SRC" "$DST" "$CSV" <<'PY'
from pathlib import Path
import sys
src, dst, csv=sys.argv[1:]
text=Path(src).read_text()
anchor='CSV=/etc/tvguard/calibration-v3.csv'
assert anchor in text
Path(dst).write_text(text.replace(anchor,'CSV='+csv,1))
states={
    ('playing','tencent'):(180,18,162,50000),
    ('paused','tencent'):(166,4,162,36000),
    ('app_home','tencent'):(53,2,51,47000),
    ('system_home','system'):(7,0,7,2700),
}
rows=[]
for (label,app),vec in states.items():
    for session in range(3):
        for i in range(8):
            rows.append(f"{1730000000+session*100+i*10},{session+1}-{label.count('a')},{label},{app},"+
                        ",".join(map(str,vec)))
Path(csv).write_text("\n".join(rows)+"\n")
PY

test "$(sh "$DST" 180 18 162 50000 | cut -d ' ' -f 1-2)" = 'playing tencent'
test "$(sh "$DST" 166 4 162 36000 | cut -d ' ' -f 1-2)" = 'paused tencent'
test "$(sh "$DST" 53 2 51 47000 | cut -d ' ' -f 1-2)" = 'app_home tencent'
test "$(sh "$DST" 7 0 7 2700 | cut -d ' ' -f 1-2)" = 'system_home system'
test "$(sh "$DST" 5000 10 4990 9000000)" = 'unknown none 0'

# Fewer than three independent sessions MUST NOT become an idle exemption hint.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[r for r in p.read_text().splitlines() if r.split(',')[1].startswith('1-')]
p.write_text('\n'.join(rows)+'\n')
PY
test "$(sh "$DST" 7 0 7 2700)" = 'unknown none 0'

# Deliberately overlapping real-world-style windows must abstain even with
# three 120-second sessions and nearly identical class centroids.
python3 - "$CSV" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
vectors={
  "playing":(100,2,97,50000),
  "paused":(100,2,97,50000),
  "app_home":(35,1,33,18000),
}
for label, vals in vectors.items():
    for sid in range(3):
        for i in range(8):
            rows.append(f"{1730000000+sid*120+i*10},{sid+1}-1,{label},tencent," +
                        ",".join(map(str, vals)))
p.write_text("\n".join(rows)+"\n")
PY
test "$(sh "$DST" 100 2 97 50000)" = 'unknown none 0'
# An exact match to the app home range remains a shadow-only diagnostic.
test "$(sh "$DST" 35 1 33 18000 | cut -d ' ' -f 1-2)" = 'app_home tencent'

# An incomplete training set must not classify any app state.
grep -v ',paused,tencent,' "$CSV" > "$TMP/partial.csv"
mv "$TMP/partial.csv" "$CSV"
test "$(sh "$DST" 35 1 33 18000)" = 'unknown none 0'
echo 'PASS: complete-scene gate, conflicting window abstention and cautious hints'
