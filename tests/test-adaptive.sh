#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/state" "$TMP/run"
SRC="$ROOT/root/usr/libexec/tvguard-adaptive"
DST="$TMP/adaptive"
python3 - "$SRC" "$DST" "$TMP/state" "$TMP/run/window.csv" <<'PY'
from pathlib import Path
import sys
src,dst,state,window=sys.argv[1:]
s=Path(src).read_text()
anchor='DATA=/usr/libexec/tvguard-data\nDIR="$("$DATA" root)"'
assert anchor in s
s=s.replace(anchor,'DIR='+state,1)
s=s.replace('WINDOW=/var/run/tvguard-adaptive-window.csv','WINDOW='+window,1)
s=s.replace('mkdir -p /var/run','mkdir -p '+str(Path(window).parent),1)
Path(dst).write_text(s)
PY
chmod +x "$DST"

cat > "$TMP/state/learning-sessions.csv" <<'EOF'
1794211178,1794211096-91,playing,general,180,stopped,8,82,44,8,18,105,10,7,4737,15493,bursty,low
1794211425,1794211242-93,playing,general,180,completed,17,174,94,138,160,233,12,143,50891,65964,variable,high
1794211713,1794211523-95,app_home,general,180,completed,18,185,100,28,41,61,0,40,37580,58416,variable,high
1794211989,1794211806-97,system_home,system,180,completed,17,174,94,9,14,34,0,13,6409,29194,bursty,high
1794212224,1794212044-99,playing,general,180,completed,17,174,94,168,402,715,134,256,47375,99570,variable,high
1794212543,1794212354-101,paused,general,180,completed,18,185,100,12,18,101,2,14,4501,16262,bursty,high
1794214061,1794213872-104,paused,general,180,completed,18,185,100,19,21,35,2,17,2991,8020,variable,high
1794214308,1794214124-106,paused,general,180,completed,17,175,94,45,115,184,2,114,166296,380772,variable,high
EOF

cat > "$TMP/state/calibration-v3.csv" <<'EOF'
1794211251,1794211242-93,playing,general,178,9,168,53288
1794211262,1794211242-93,playing,general,276,140,136,50891
1794211272,1794211242-93,playing,general,155,15,139,44952
1794211282,1794211242-93,playing,general,233,100,133,64425
1794211292,1794211242-93,playing,general,138,12,125,48192
1794211302,1794211242-93,playing,general,175,53,121,35397
1794211313,1794211242-93,playing,general,160,27,133,37888
1794211323,1794211242-93,playing,general,173,4,168,48306
1794211333,1794211242-93,playing,general,184,35,148,59241
1794211343,1794211242-93,playing,general,172,7,164,65964
1794211354,1794211242-93,playing,general,156,12,143,58888
1794211364,1794211242-93,playing,general,156,8,147,51505
1794211374,1794211242-93,playing,general,157,14,142,39695
1794211384,1794211242-93,playing,general,156,5,151,41231
1794211394,1794211242-93,playing,general,130,10,119,36118
1794211405,1794211242-93,playing,general,158,0,158,64708
1794211415,1794211242-93,playing,general,163,0,162,128439
1794212050,1794212044-99,playing,general,572,142,426,99570
1794212060,1794212044-99,playing,general,726,257,460,122505
1794212071,1794212044-99,playing,general,566,181,381,64970
1794212081,1794212044-99,playing,general,468,52,416,85817
1794212091,1794212044-99,playing,general,404,29,374,69291
1794212101,1794212044-99,playing,general,284,36,247,32878
1794212112,1794212044-99,playing,general,168,7,158,20982
1794212122,1794212044-99,playing,general,139,5,129,17653
1794212132,1794212044-99,playing,general,238,17,216,35899
1794212142,1794212044-99,playing,general,463,202,256,47375
1794212153,1794212044-99,playing,general,715,424,285,60305
1794212163,1794212044-99,playing,general,518,177,339,53764
1794212173,1794212044-99,playing,general,402,117,281,54443
1794212183,1794212044-99,playing,general,216,11,204,43959
1794212193,1794212044-99,playing,general,358,170,187,39106
1794212204,1794212044-99,playing,general,309,134,174,34529
1794212214,1794212044-99,playing,general,326,137,189,40827
1794212357,1794212354-101,paused,general,16,0,15,4501
1794212367,1794212354-101,paused,general,101,59,42,16262
1794212378,1794212354-101,paused,general,35,13,22,7255
1794212388,1794212354-101,paused,general,27,10,17,6015
1794212398,1794212354-101,paused,general,22,8,14,6270
1794212408,1794212354-101,paused,general,16,0,15,4420
1794212419,1794212354-101,paused,general,12,0,12,3740
1794212429,1794212354-101,paused,general,11,1,10,3094
1794212439,1794212354-101,paused,general,44,30,13,6598
1794212449,1794212354-101,paused,general,18,0,18,3594
1794212461,1794212354-101,paused,general,34,17,17,7864
1794212471,1794212354-101,paused,general,25,11,13,7007
1794212481,1794212354-101,paused,general,17,1,15,5167
1794212491,1794212354-101,paused,general,106,62,44,19993
1794212502,1794212354-101,paused,general,14,2,11,3892
1794212512,1794212354-101,paused,general,18,4,13,4177
1794212522,1794212354-101,paused,general,13,0,12,3286
1794212532,1794212354-101,paused,general,13,0,13,3089
1794213876,1794213872-104,paused,general,127,105,16,12058
1794213886,1794213872-104,paused,general,35,9,19,4701
1794213896,1794213872-104,paused,general,23,1,17,2682
1794213907,1794213872-104,paused,general,21,3,15,2925
1794213917,1794213872-104,paused,general,24,1,17,2827
1794213927,1794213872-104,paused,general,25,6,18,3962
1794213937,1794213872-104,paused,general,20,2,16,4420
1794213948,1794213872-104,paused,general,20,1,17,2991
1794213958,1794213872-104,paused,general,20,1,17,2502
1794213968,1794213872-104,paused,general,21,1,16,2867
1794213979,1794213872-104,paused,general,21,0,16,2497
1794213989,1794213872-104,paused,general,24,5,17,3990
1794213999,1794213872-104,paused,general,18,2,16,3939
1794214010,1794213872-104,paused,general,20,0,18,2991
1794214020,1794213872-104,paused,general,24,2,20,3739
1794214030,1794213872-104,paused,general,31,9,18,8020
1794214040,1794213872-104,paused,general,19,1,16,2257
1794214051,1794213872-104,paused,general,23,7,16,4012
1794214133,1794214124-106,paused,general,326,174,140,93406
1794214143,1794214124-106,paused,general,131,5,118,87446
1794214154,1794214124-106,paused,general,184,29,154,200676
1794214164,1794214124-106,paused,general,147,4,141,204399
1794214174,1794214124-106,paused,general,140,3,135,222093
1794214184,1794214124-106,paused,general,137,2,134,244101
1794214195,1794214124-106,paused,general,96,0,96,356009
1794214205,1794214124-106,paused,general,115,0,114,650334
1794214215,1794214124-106,paused,general,68,4,64,166296
1794214226,1794214124-106,paused,general,45,0,45,98272
1794214236,1794214124-106,paused,general,55,1,54,108605
1794214246,1794214124-106,paused,general,41,0,40,16471
1794214256,1794214124-106,paused,general,56,0,56,117879
1794214267,1794214124-106,paused,general,54,4,49,127608
1794214277,1794214124-106,paused,general,61,2,59,155079
1794214287,1794214124-106,paused,general,168,2,165,252520
1794214298,1794214124-106,paused,general,174,1,172,380772
EOF

run() { sh "$DST" "$@"; }

# Phase 1: the stopped/low playing session is ignored, so idle and active
# boundaries come only from completed+high sessions.
out="$(run 1000 12 1 10 4000)"
echo "$out" | grep -q '^warming '
echo "$out" | awk '{exit !($6==138 && $5>=66 && $5<=76)}'

run 1010 9 0 8 3200 >/dev/null
run 1020 16 5 11 4238 >/dev/null
out="$(run 1030 12 2 9 3818)"
echo "$out" | grep -q '^idle '
echo "$out" | awk '{exit !($7<=41 && $8<=61)}'

out="$(run 1040 160 12 143 50891)"
echo "$out" | grep -q '^active 100 '

# Sustained ~115 PPS remains active from rolling context even below active P10.
run 2000 110 70 40 18000 >/dev/null
run 2010 115 77 38 18109 >/dev/null
run 2020 120 75 45 19000 >/dev/null
out="$(run 2030 116 74 42 18500)"
echo "$out" | grep -Eq '^active (85|95|100) '

# Phase 2A prototype A: low-activity pause overlaps home idle. It may produce
# a diagnostic hint, but exact pause vs homepage is intentionally not claimed.
run 3000 35 9 19 4701 >/dev/null
run 3010 23 1 17 2682 >/dev/null
run 3020 21 3 15 2925 >/dev/null
out="$(run 3030 24 1 17 2827)"
echo "$out" | awk '{exit !($1=="idle" && $9=="idle_overlap" && $10==60)}'

# Prototype B: low median + occasional PPS burst is ambiguous for billing.
run 4000 16 0 15 4501 >/dev/null
run 4010 101 59 42 16262 >/dev/null
run 4020 35 13 22 7255 >/dev/null
out="$(run 4030 18 0 18 3594)"
echo "$out" | awk '{exit !($1=="ambiguous" && $9=="bursty_pause" && $10==75)}'

# Prototype C: Tencent-like pause has playing-like PPS but a much larger
# rolling B/P ratio. Phase 2A recognizes the hint yet MUST keep Phase 1
# billing state active/ambiguous rather than granting free time.
run 5000 131 5 118 87446 >/dev/null
run 5010 184 29 154 200676 >/dev/null
run 5020 147 4 141 204399 >/dev/null
run 5030 140 3 135 222093 >/dev/null
run 5040 137 2 134 244101 >/dev/null
out="$(run 5050 96 0 96 356009)"
echo "$out" | awk '{exit !(($1=="active" || $1=="ambiguous") && $9=="high_ratio_pause" && $10>=90 && $11>=800)}'

# Normal playback has much lower B/P and must never inherit the high-ratio
# pause hint, even when PPS occupies the same broad region.
run 6000 178 9 168 53288 >/dev/null
run 6010 276 140 136 50891 >/dev/null
run 6020 155 15 139 44952 >/dev/null
run 6030 233 100 133 64425 >/dev/null
run 6040 138 12 125 48192 >/dev/null
out="$(run 6050 175 53 121 35397)"
echo "$out" | awk '{exit !($1=="active" && $9=="none" && $11<800)}'

# N1 real-device r5 regression: normal playback was clean, Tencent pause
# produced high_ratio_pause, but after playback resumed the rolling B/P
# remained high. Clear current active evidence must veto the pause hint.
run 7000 100 0 100 195330 >/dev/null
run 7010 118 2 116 240000 >/dev/null
run 7020 194 4 190 300000 >/dev/null
run 7030 112 1 111 260000 >/dev/null
run 7040 130 2 128 390000 >/dev/null
out="$(run 7050 144 3 141 723214)"
echo "$out" | awk '{exit !($1=="active" && $9=="none" && $11>=1000)}'

# Strongly rising playback must also veto a high-ratio pause hint even when
# the latest PPS is temporarily below active_floor.
run 8000 70 0 70 140000 >/dev/null
run 8010 82 1 81 170000 >/dev/null
run 8020 92 1 91 210000 >/dev/null
run 8030 105 2 103 260000 >/dev/null
run 8040 120 2 118 320000 >/dev/null
out="$(run 8050 126 2 124 350000)"
echo "$out" | awk '{exit !($9=="none" && $14 < -20)}'

echo 'PASS: adaptive phase2A keeps phase1 billing and learns pause prototypes'
