#!/usr/bin/env bash
# Builds a release Lumen.app into ./build. Requires: Swift toolchain, `brew install mpv`.
# Pass --install to also copy it into /Applications (so Spotlight/Raycast can find it).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Lumen"
APP="build/Lumen.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lumen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Lumen 2>/dev/null || true
  rm -rf /Applications/Lumen.app
  ditto "$APP" /Applications/Lumen.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Lumen.app
  echo "Installed /Applications/Lumen.app"
fi
