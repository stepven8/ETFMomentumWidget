#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ETFMomentumApp"
APP_DIR="/Applications/${APP_NAME}.app"

cd "$ROOT"
xcodebuild \
  -project ETFMomentumWidget.xcodeproj \
  -scheme ETFMomentumApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

BUILT_APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*ETFMomentumWidget*/Build/Products/Debug/ETFMomentumApp.app' -type d | head -1)"
if [[ -z "$BUILT_APP" ]]; then
  echo "未找到 Xcode 构建产物 ETFMomentumApp.app" >&2
  exit 1
fi

rm -rf "$APP_DIR"
ditto "$BUILT_APP" "$APP_DIR"
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP_DIR" 2>/dev/null || true
echo "$APP_DIR"
