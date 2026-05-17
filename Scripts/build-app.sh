#!/usr/bin/env bash
# Build DoShot.app from the SwiftPM executable target.
#
# - Compiles a Release binary via `swift build`
# - Wraps it in a proper macOS `.app` bundle structure
# - Copies Info.plist and bundled resources (KeyboardShortcuts strings, directive.md)
# - Codesigns with Developer ID + hardened runtime when CODESIGN_IDENTITY is set
#   (or auto-discovered from the keychain); falls back to ad-hoc otherwise.
#   Hardened runtime is required for notarization — see Scripts/notarize.sh.
#
# Output: dist/DoShot.app

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DoShot"
APP_DIR="dist/${APP_NAME}.app"
BIN_NAME="DoShot"
ARCH=$(uname -m)

echo "==> Cleaning previous build…"
rm -rf "$APP_DIR"

echo "==> swift build -c release…"
swift build -c release --arch arm64 --arch x86_64

# Find the universal binary.
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${BIN_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling ${APP_DIR}…"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "$BIN_PATH" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
cp AppBundle/Info.plist "${APP_DIR}/Contents/Info.plist"
if [[ -f AppBundle/AppIcon.icns ]]; then
  cp AppBundle/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
  echo "WARN: AppBundle/AppIcon.icns missing — run Scripts/build-icon.sh to regenerate." >&2
fi

# Copy the SwiftPM-generated resource bundle (DoShot_DoShot.bundle) into Resources.
BIN_DIR="$(dirname "$BIN_PATH")"
if compgen -G "${BIN_DIR}/${BIN_NAME}_${BIN_NAME}.bundle" > /dev/null; then
  cp -R "${BIN_DIR}/${BIN_NAME}_${BIN_NAME}.bundle" "${APP_DIR}/Contents/Resources/"
fi

# Copy KeyboardShortcuts localized strings bundle if produced.
for b in "${BIN_DIR}"/*.bundle; do
  [[ -e "$b" ]] || continue
  cp -R "$b" "${APP_DIR}/Contents/Resources/"
done

# Pick a signing identity: explicit override > Developer ID from keychain > ad-hoc.
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }' || true)"
fi
ENTITLEMENTS="AppBundle/DoShot.entitlements"

if [[ -n "${CODESIGN_IDENTITY}" && -f "${ENTITLEMENTS}" ]]; then
  echo "==> Codesigning with Developer ID + hardened runtime…"
  echo "    Identity: ${CODESIGN_IDENTITY}"
  # Sign the inner binary first, then the bundle. --deep is deprecated for
  # release signing; signing nested resources explicitly avoids the warning.
  codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${CODESIGN_IDENTITY}" \
    "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
  codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${CODESIGN_IDENTITY}" \
    "${APP_DIR}"
  echo "==> Done: ${APP_DIR} (signed, ready for Scripts/notarize.sh)"
else
  echo "==> No Developer ID identity found — ad-hoc codesigning…"
  codesign --force --deep --sign - "${APP_DIR}"
  echo "==> Done: ${APP_DIR}"
  echo "    Right-click → Open on first launch to bypass Gatekeeper (unsigned)."
fi
