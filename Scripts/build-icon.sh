#!/usr/bin/env bash
# Generate AppBundle/AppIcon.icns from the programmatic master.
# Re-run anytime gen-icon.swift changes. The output .icns is checked in
# so the build doesn't depend on this script for routine .app builds.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "==> Rendering master 1024×1024…"
swift Scripts/gen-icon.swift "$ICONSET/icon_512x512@2x.png"

echo "==> Deriving size variants via sips…"
sips -z 16 16   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_512x512.png"    >/dev/null

echo "==> iconutil → AppBundle/AppIcon.icns"
iconutil -c icns "$ICONSET" -o AppBundle/AppIcon.icns

rm -rf "$WORK"
echo "==> Done"
