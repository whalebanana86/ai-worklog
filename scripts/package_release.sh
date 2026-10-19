#!/bin/bash
# GitHub Releases 에 올릴 설치 파일을 만든다: build/release/AI-Worklog-<버전>-macOS.dmg / .zip
#   scripts/package_release.sh 1.0.0
# Apple 개발자 인증서가 있으면 서명·공증까지 한다 (없으면 임시 서명).
#   SIGN_IDENTITY="Developer ID Application: 이름 (TEAMID)"   서명
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD                 공증 (앱 암호: appleid.apple.com 에서 만든 것)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?버전을 주세요. 예: scripts/package_release.sh 1.0.0}"
NAME="AI 작업일지"
APP="build/$NAME.app"
OUT="build/release"
BASE="AI-Worklog-$VERSION-macOS"

# 두 아키텍처(Apple 실리콘·인텔)로 만들고, 만든 앱에만 버전을 적는다 (저장소의 Support/Info.plist 는 그대로).
UNIVERSAL=1 scripts/build_app.sh
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "서명: $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    echo "공증 받는 중…"
    ditto -c -k --keepParent "$APP" build/notarize.zip
    xcrun notarytool submit build/notarize.zip --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$APP"
    rm -f build/notarize.zip
  else
    echo "공증 정보가 없어 서명만 했어요."
  fi
else
  echo "개발자 인증서가 없어 임시 서명으로 만들어요 (처음 열 때 '그래도 열기'가 필요해요)."
  codesign --force --sign - "$APP" >/dev/null
fi

rm -rf "$OUT" build/dmg
mkdir -p "$OUT" build/dmg
ditto -c -k --keepParent "$APP" "$OUT/$BASE.zip"
# DMG: 앱과 '응용 프로그램' 바로 가기를 나란히 두어 끌어다 놓으면 설치되게.
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname "AI Worklog" -srcfolder build/dmg -ov -format UDZO "$OUT/$BASE.dmg"
rm -rf build/dmg
[ -n "${SIGN_IDENTITY:-}" ] && codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT/$BASE.dmg"
(cd "$OUT" && shasum -a 256 "$BASE.dmg" "$BASE.zip" > SHA256SUMS.txt)
ls -lh "$OUT"
