#!/bin/bash
# 화면 캡처·녹화용 앱 사본. 다른 스크립트가 `source scripts/demo_app.sh` 로 불러 쓴다 (저장소 맨 위 폴더에서).
#
# 빌드한 앱을 그대로 띄우면 앱 ID(local.aiworklog)가 설치된 앱과 같아서
#   - 끌 때 `pkill -x AIWorkLog` 가 켜 두고 쓰던 앱까지 끄고,
#   - 창·사이드바·정보 패널 크기 같은 설정을 설치된 앱의 설정 위에 덮어쓴다.
# 그래서 앱 ID 만 바꾼 사본(build.noindex/demo/AIWorkLogDemo.app, local.aiworklog.demo)을 띄우고, 그 사본만 골라 끈다.
# 사본은 띄울 때마다 빈 설정으로 시작하고, 끝나면 그 설정을 지운다.
#
#   demo_prepare            빌드한 앱으로 사본을 만든다 (앱이 바뀌었을 때만 다시)
#   demo_open [옵션...]     사본을 빈 설정으로 띄우고 창이 뜰 때까지 기다린다 → $DEMO_PID
#   demo_quit               사본만 끈다
#   demo_finish             사본을 끄고 그 설정을 지운다 (trap demo_finish EXIT 로 쓴다)

DEMO_ID=local.aiworklog.demo
DEMO_APP=build.noindex/demo/AIWorkLogDemo.app
# 경로에 한글이 섞이면 pgrep -f 가 못 찾을 때가 있어 사본 이름은 영어로 둔다.
DEMO_MATCH='AIWorkLogDemo\.app/Contents/MacOS/AIWorkLog'
DEMO_PID=""

demo_prepare() {
  local src="build.noindex/이걸내가.app" stamp=build.noindex/demo/.prepared
  [ -d "$src" ] || scripts/build_app.sh >/dev/null
  if [ -d "$DEMO_APP" ] && [ -f "$stamp" ] && [ -z "$(find "$src" -newer "$stamp" -print -quit)" ]; then return 0; fi
  demo_quit
  rm -rf "$DEMO_APP"
  mkdir -p build.noindex/demo
  ditto "$src" "$DEMO_APP"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEMO_ID" "$DEMO_APP/Contents/Info.plist"
  codesign --force --sign - "$DEMO_APP" >/dev/null 2>&1
  touch "$stamp"
}

demo_reset() {
  defaults delete "$DEMO_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Saved Application State/$DEMO_ID.savedState"
}

demo_quit() {
  pkill -f "$DEMO_MATCH" 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -f "$DEMO_MATCH" >/dev/null || return 0
    sleep 0.25
  done
}

demo_open() {
  demo_quit
  demo_reset
  # 지난번 창 상태(크기·사이드바 너비)를 macOS 가 되살리지 않게 해서 늘 처음 연 모습으로 찍는다.
  open -n "$DEMO_APP" --args "$@" -ApplePersistenceIgnoreState YES
  DEMO_PID=""
  for i in $(seq 1 40); do
    DEMO_PID=$(pgrep -nf "$DEMO_MATCH" || true)
    if [ -n "$DEMO_PID" ] && swift scripts/window_id.swift "$DEMO_PID" >/dev/null 2>&1; then return 0; fi
    # 터미널에서 띄운 앱은 앞으로 나오지 못해 창을 안 만들 때가 있다. 한 번 더 열면 (다시 열기) 창이 생긴다.
    [ -n "$DEMO_PID" ] && [ "$i" = 6 ] && open "$DEMO_APP"
    sleep 0.5
  done
  echo "앱 창이 뜨지 않았어요" >&2
  return 1
}

demo_finish() {
  demo_quit
  demo_reset
}
