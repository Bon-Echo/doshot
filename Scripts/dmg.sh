#!/usr/bin/env bash
# Package dist/DoShot.app into an unsigned DMG via `create-dmg`.
# Install create-dmg: `brew install create-dmg`.
#
# Output: dist/DoShot-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DoShot"
APP_DIR="dist/${APP_NAME}.app"

if [[ ! -d "$APP_DIR" ]]; then
  echo "==> ${APP_DIR} not found — running Scripts/build-app.sh first."
  bash Scripts/build-app.sh
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_DIR}/Contents/Info.plist")"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg not installed. Run: brew install create-dmg" >&2
  exit 1
fi

rm -f "$DMG_PATH"

echo "==> Building ${DMG_PATH}…"
create-dmg \
  --volname "${APP_NAME} ${VERSION}" \
  --window-pos 200 120 \
  --window-size 540 320 \
  --icon-size 96 \
  --icon "${APP_NAME}.app" 140 150 \
  --app-drop-link 400 150 \
  --no-internet-enable \
  --skip-jenkins \
  "$DMG_PATH" \
  "$APP_DIR"

echo "==> Done: $DMG_PATH"
echo "    DMG is unsigned — first launch requires right-click → Open."
