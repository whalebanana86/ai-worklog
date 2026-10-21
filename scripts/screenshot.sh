#!/bin/bash
# 앱을 지정한 화면으로 띄우고 앱 창만 찍는다.  사용: scripts/screenshot.sh <저장할 png> [앱 실행 옵션...]
#   예) scripts/screenshot.sh /tmp/a.png --demo --screen timeline --period week
#   WINDOW=<창 제목 일부> 를 주면 그 창을 찍는다 (예: WINDOW=설정 … --settings)
# 앱 ID 만 바꾼 사본으로 찍는다. 켜 둔 앱은 끄지 않고, 그 창·패널 크기 설정도 건드리지 않는다 (scripts/demo_app.sh).
# --demo 없이 찍으면 실제 기록과 보관함을 읽는다.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; shift
source scripts/demo_app.sh
trap demo_finish EXIT
demo_prepare
demo_open "$@"
sleep "${WAIT:-3}"
ID=$(swift scripts/window_id.swift "$DEMO_PID" ${WINDOW:+"$WINDOW"})
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
