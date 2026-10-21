#!/bin/bash
# README 그림을 지어낸 기록(--demo)으로 다시 찍는다. 실제 기록은 찍히지 않는다.
#   scripts/make_screenshots.sh ko   → docs/screenshots/*.png
#   scripts/make_screenshots.sh en   → docs/screenshots/en/*.png
# 앱 ID 만 바꾼 사본으로 찍어서 켜 둔 앱은 그대로 둔다 (scripts/demo_app.sh). 창 자리는 FRAME=x,y,w,h 로 바꾼다.
set -euo pipefail
cd "$(dirname "$0")/.."
LANG_CODE="${1:-ko}"
OUT="docs/screenshots"; [ "$LANG_CODE" = ko ] || OUT="docs/screenshots/$LANG_CODE"
mkdir -p "$OUT" build/shots
source scripts/demo_app.sh
trap demo_finish EXIT
demo_prepare
F="${FRAME:-60,0,1400,940}"
P="$HOME/Projects/todo-app"
# macOS 가 붙이는 글(설정 창 제목 등)도 그 언어로 나오게 -AppleLanguages 를 함께 준다.
SYS=(-AppleLanguages "($LANG_CODE)")
shot() { local name="$1"; shift; scripts/screenshot.sh "build/shots/$name.png" --demo --lang "$LANG_CODE" "${SYS[@]}" "$@" >/dev/null; sips -Z 1600 "build/shots/$name.png" --out "$OUT/$name.png" >/dev/null; }
shot dashboard --period month --frame "$F"
shot project --screen "project=$P" --period month --frame "$F"
shot session --session demo-todo-app-2 --frame "$F"
shot skills --screen skills --frame "$F"
shot project-dark --dark --screen "project=$P" --period month --frame "$F"
# 설정 창은 가장 큰 창이 아니라 제목으로 찾는다.
demo_open --demo --lang "$LANG_CODE" "${SYS[@]}" --settings
sleep 4
ID=""
for TITLE in 설정 Settings 設定; do
  ID=$(swift scripts/window_id.swift "$DEMO_PID" "$TITLE" 2>/dev/null || true)
  [ -n "$ID" ] && break
done
[ -n "$ID" ] || { echo "설정 창을 찾지 못했어요"; exit 1; }
screencapture -x -o -l "$ID" "$OUT/settings.png"
ls -1 "$OUT"
