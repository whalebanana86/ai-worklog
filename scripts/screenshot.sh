#!/bin/bash
# 앱을 지정한 화면으로 띄우고 앱 창만 찍는다.  사용: scripts/screenshot.sh <저장할 png> [앱 실행 옵션...]
#   예) scripts/screenshot.sh /tmp/a.png --screen timeline --period week
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; shift
pkill -x AIWorkLog 2>/dev/null || true
sleep 0.5
open -n "build/AI 작업일지.app" --args "$@"
for _ in $(seq 1 40); do
  PID=$(pgrep -nx AIWorkLog || true)
  if [ -n "$PID" ] && swift scripts/window_id.swift "$PID" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
sleep "${WAIT:-3}"
ID=$(swift scripts/window_id.swift "$PID")
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
