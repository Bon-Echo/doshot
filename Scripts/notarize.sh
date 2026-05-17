#!/usr/bin/env bash
# Notarize dist/DoShot.app and, if present, dist/DoShot-<version>.dmg.
#
# Prereqs:
#   - dist/DoShot.app already signed with Developer ID + hardened runtime
#     (run Scripts/build-app.sh first).
#   - `xcrun notarytool` keychain profile stored as $NOTARY_PROFILE
#     (defaults to AC_PASSWORD). Create one with:
#       xcrun notarytool store-credentials AC_PASSWORD \
#         --apple-id <id> --team-id <team> --password <app-specific>
#
# Flow:
#   1. Zip the .app for submission (notarytool wants a flat archive).
#   2. Submit and wait for Apple's verdict (can take 1–15 min).
#   3. Staple the ticket onto the .app so Gatekeeper accepts it offline.
#   4. If a matching DMG exists, repackage it around the stapled .app,
#      submit the DMG, and staple it as well.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DoShot"
APP_DIR="dist/${APP_NAME}.app"
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "${APP_DIR} not found — run Scripts/build-app.sh first." >&2
  exit 1
fi

# Refuse to ship an ad-hoc-signed bundle to the notary service.
# Authority lines only appear at verbose>=2; awk-exit-early would SIGPIPE
# codesign and trip pipefail, so read all output then grep.
SIG_INFO="$(codesign -dv --verbose=2 "$APP_DIR" 2>&1 || true)"
SIG_AUTHORITY="$(printf '%s\n' "$SIG_INFO" | grep -m1 '^Authority=' | head -1 | cut -d'=' -f2-)"
if [[ -z "$SIG_AUTHORITY" || "$SIG_AUTHORITY" == "-" || "$SIG_AUTHORITY" != Developer\ ID\ Application* ]]; then
  echo "${APP_DIR} is not signed with Developer ID (authority='${SIG_AUTHORITY:-none}')." >&2
  echo "Run Scripts/build-app.sh on a Mac with the Developer ID identity in its keychain." >&2
  exit 1
fi

ZIP_PATH="dist/${APP_NAME}-notarize.zip"
echo "==> Zipping ${APP_DIR} → ${ZIP_PATH}…"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Submitting ${ZIP_PATH} (profile: ${PROFILE})…"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$PROFILE" \
  --wait

echo "==> Stapling ${APP_DIR}…"
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
rm -f "$ZIP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_DIR}/Contents/Info.plist")"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

if [[ -f "$DMG_PATH" ]]; then
  # The pre-notarization DMG wraps an un-stapled .app — rebuild around the
  # stapled bundle so the copy on disk includes the ticket.
  echo "==> Rebuilding ${DMG_PATH} around stapled .app…"
  bash Scripts/dmg.sh
  # Codesign the DMG itself so spctl is happy when the file is downloaded
  # without quarantine (notarization+staple covers Gatekeeper, but signing
  # the container is standard practice and required by some distributors).
  echo "==> Codesigning ${DMG_PATH}…"
  codesign --force --timestamp --sign "${SIG_AUTHORITY}" "$DMG_PATH"
  echo "==> Submitting ${DMG_PATH}…"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$PROFILE" \
    --wait
  echo "==> Stapling ${DMG_PATH}…"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "==> Notarization complete."
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier|Runtime'
