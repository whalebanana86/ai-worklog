#!/bin/bash
# README 첫머리의 20초 시연 영상을 만든다: 지어낸 기록(--demo)으로 앱을 띄워 자동으로 둘러보고(--tour), 앱 창만 녹화한다.
#   scripts/make_demo_video.sh ko   → docs/demo-ko.gif, docs/demo-ko.mp4
#   scripts/make_demo_video.sh en   → docs/demo-en.gif, docs/demo-en.mp4
# 필요한 것: macOS 15+, ffmpeg, 화면 기록 권한(터미널).
set -euo pipefail
cd "$(dirname "$0")/.."
LANG_CODE="${1:-ko}"
mkdir -p build docs
[ -x build/record_window ] && [ build/record_window -nt scripts/record_window.swift ] || \
  swiftc -O -parse-as-library scripts/record_window.swift -o build/record_window
[ -d "build/AI 작업일지.app" ] || scripts/build_app.sh >/dev/null

pkill -x AIWorkLog 2>/dev/null || true
sleep 0.5
open -n "build/AI 작업일지.app" --args --demo --lang "$LANG_CODE" --tour --frame 60,0,1400,900
PID=""
for _ in $(seq 1 40); do
  PID=$(pgrep -nx AIWorkLog || true)
  if [ -n "$PID" ] && swift scripts/window_id.swift "$PID" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
RAW="build/demo-$LANG_CODE-raw.mp4"
build/record_window "$PID" 24 "$RAW" >/dev/null
pkill -x AIWorkLog 2>/dev/null || true

# 둘러보기는 창이 뜨고 1.5초 뒤 시작해 20초쯤 걸린다.
ffmpeg -v error -y -ss 1.2 -t 21 -i "$RAW" -vf "scale=1400:-2:flags=lanczos" -c:v libx264 -crf 26 -preset slow -pix_fmt yuv420p -movflags +faststart "docs/demo-$LANG_CODE.mp4"
ffmpeg -v error -y -ss 1.2 -t 21 -i "$RAW" \
  -vf "fps=10,scale=1100:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "docs/demo-$LANG_CODE.gif"
ls -lh "docs/demo-$LANG_CODE.gif" "docs/demo-$LANG_CODE.mp4" | awk '{print $5, $9}'
