#!/bin/bash
# "AI 작업일지.app" 을 만든다.
#   scripts/build_app.sh                         build/ 에 앱만 만들기
#   scripts/build_app.sh --install               ~/Applications 에 설치하고 보관함을 미리 채우기 (+ 지난 날짜 AI 요약)
#   scripts/build_app.sh --install --no-summary  AI 요약은 미리 만들지 않기 (앱에서 날짜를 볼 때 그날만 요약)
#   scripts/build_app.sh --install --auto-sync   + 앱을 안 열어도 6시간마다 보관함 갱신 (launchd)
#   scripts/build_app.sh --remove-auto-sync      자동 보관 끄기
#   (AI 요약 미리 만들기·자동 보관은 앱 설정(⌘,)에서도 켜고 끌 수 있어요)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="AI 작업일지"
APP="build/$NAME.app"
INSTALLED="$HOME/Applications/$NAME.app"
AGENT_ID="local.aiworklog.sync"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_ID.plist"

remove_agent() {
  if [ -f "$AGENT_PLIST" ]; then
    launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
    echo "자동 보관을 껐어요."
  fi
}

if [ "${1:-}" = "--remove-auto-sync" ]; then
  if [ -x "$INSTALLED/Contents/MacOS/AIWorkLog" ]; then
    "$INSTALLED/Contents/MacOS/AIWorkLog" cli --auto-sync off
  else
    remove_agent
  fi
  exit 0
fi

# 아이콘이 없으면 한 번 그리고 256색으로 줄여 묶는다 (PIL 이 없으면 줄이지 않고 묶기만).
if [ ! -f Support/AppIcon.icns ]; then
  swift scripts/make_icon.swift build >/dev/null
  python3 scripts/compress_icon.py build/AppIcon.iconset Support/AppIcon.icns
fi

# 크기 우선 최적화(-Osize). 일반 release 빌드와 섞이지 않게 빌드 폴더를 따로 쓴다.
BUILD_PATH=".build/app-release"
swift build -c release --product AIWorkLog -Xswiftc -Osize --build-path "$BUILD_PATH"
BIN="$(swift build -c release --product AIWorkLog -Xswiftc -Osize --build-path "$BUILD_PATH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AIWorkLog" "$APP/Contents/MacOS/AIWorkLog"
# 디버그 기호를 지운다 (실행 파일 3.6MB → 1.5MB 안팎). 터미널 명령은 같은 실행 파일의 `cli` 모드라 따로 넣지 않는다.
strip -x "$APP/Contents/MacOS/AIWorkLog"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 내 맥에서만 쓰는 앱이라 개발자 인증서 없이 임시 서명한다.
codesign --force --sign - "$APP" >/dev/null
echo "만들었어요: $APP ($(du -sh "$APP" | cut -f1))"

for arg in "$@"; do
  case "$arg" in
    --install)
      mkdir -p "$HOME/Applications"
      pkill -x AIWorkLog 2>/dev/null || true
      rm -rf "$INSTALLED"
      cp -R "$APP" "$HOME/Applications/"
      echo "설치했어요: ~/Applications/$NAME.app"
      echo "보관함을 준비하는 중이에요 (처음 한 번은 기록 전체를 읽어요)…"
      "$INSTALLED/Contents/MacOS/AIWorkLog" cli --quiet
      # 지난 날짜 AI 요약을 처음 한 번 모두 만들어 보관함에 남긴다. 앱은 저장된 요약을 불러 보여 주기만 해서 토큰을 다시 쓰지 않는다.
      # 이미 요약한 날은 건너뛰니, 중간에 멈추거나 다시 설치해도 남은 날만 한다.
      case " $* " in
        *" --no-summary "*) echo "AI 요약은 건너뛰었어요 (--no-summary)." ;;
        *) "$INSTALLED/Contents/MacOS/AIWorkLog" cli --summarize || echo "AI 요약을 다 만들지 못했어요. 다시 설치하거나 앱에서 날짜를 보면 남은 날을 요약해요." ;;
      esac
      ;;
    --auto-sync)
      [ -d "$INSTALLED" ] || { echo "먼저 --install 로 설치해 주세요."; exit 1; }
      # 앱 설정의 "자동 보관"과 같은 것을 켠다 (launchd, 6시간마다 cli --quiet).
      "$INSTALLED/Contents/MacOS/AIWorkLog" cli --auto-sync on
      ;;
  esac
done
