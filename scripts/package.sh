#!/usr/bin/env bash
# Builds a self-contained Lumen.app (libmpv and every dependency copied into Contents/Frameworks)
# and a drag-to-install DMG in ./build. Requires: Swift toolchain, `brew install mpv dylibbundler`.
#
# The bundled Homebrew libraries target the macOS version and CPU they were built for
# (currently macOS 26+, Apple Silicon), so the package runs on Macs that match.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh >/dev/null
APP="build/Lumen.app"
FRAMEWORKS="$APP/Contents/Frameworks"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Lumen-$VERSION.dmg"

echo "Bundling libraries…"
rm -rf "$FRAMEWORKS"
mkdir -p "$FRAMEWORKS"
# -cd: create dir · -of: overwrite · -b: bundle deps · -s: search path for @rpath dependencies
dylibbundler -cd -of -b \
  -x "$APP/Contents/MacOS/Lumen" \
  -d "$FRAMEWORKS" \
  -p @executable_path/../Frameworks/ \
  -s /opt/homebrew/lib >/dev/null

# dylibbundler adds its rpath once per rewritten dependency; dyld (macOS 15+) refuses to launch a
# binary with duplicate LC_RPATH entries, so keep exactly one of each.
dedupe_rpaths() {
  local file="$1" path
  while read -r path; do
    while (( $(otool -l "$file" | grep -A2 LC_RPATH | grep -c "path $path ") > 1 )); do
      install_name_tool -delete_rpath "$path" "$file" 2>/dev/null
    done
  done < <(otool -l "$file" | grep -A2 LC_RPATH | awk '/ path /{print $2}' | sort -u)
}
dedupe_rpaths "$APP/Contents/MacOS/Lumen"
for lib in "$FRAMEWORKS"/*.dylib; do dedupe_rpaths "$lib"; done

dupes=$(for file in "$APP/Contents/MacOS/Lumen" "$FRAMEWORKS"/*.dylib; do
  otool -l "$file" | grep -A2 LC_RPATH | awk '/ path /{print $2}' | sort | uniq -d | sed "s|^|$file: |"
done)
if [[ -n "$dupes" ]]; then
  echo "error: duplicate rpaths remain:" >&2; echo "$dupes" >&2; exit 1
fi

# Every load command must now point inside the bundle (system libraries excepted).
leaks=$( { otool -L "$APP/Contents/MacOS/Lumen"; for lib in "$FRAMEWORKS"/*.dylib; do otool -L "$lib"; done; } \
  | grep -E '^\s+/(opt|usr/local)/' || true)
if [[ -n "$leaks" ]]; then
  echo "error: unbundled dependencies remain:" >&2
  echo "$leaks" | sort -u >&2
  exit 1
fi

# install_name_tool invalidated the signatures; sign libraries first, then the app.
codesign --force --sign - "$FRAMEWORKS"/*.dylib 2>/dev/null
codesign --force --sign - "$APP" 2>/dev/null
codesign --verify --strict "$APP"

# Smoke test: the bundled binary must actually launch (dyld rejects bad load commands at startup).
"$APP/Contents/MacOS/Lumen" >/dev/null 2>"$APP.launch.log" &
LAUNCH_PID=$!
sleep 4
if kill -0 "$LAUNCH_PID" 2>/dev/null; then
  kill "$LAUNCH_PID"; wait "$LAUNCH_PID" 2>/dev/null || true
  rm -f "$APP.launch.log"
else
  echo "error: bundled app failed to launch:" >&2; cat "$APP.launch.log" >&2; exit 1
fi

echo "Creating ${DMG}…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Lumen" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "Built $APP ($(du -sh "$APP" | cut -f1)) and $DMG ($(du -sh "$DMG" | cut -f1))"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Lumen 2>/dev/null || true
  rm -rf /Applications/Lumen.app
  ditto "$APP" /Applications/Lumen.app
  echo "Installed /Applications/Lumen.app"
fi
