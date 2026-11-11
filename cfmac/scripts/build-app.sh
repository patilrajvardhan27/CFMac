#!/bin/bash
# Builds build/cfmac.app. Needs only the Xcode Command Line Tools and network access the
# first time (to fetch the licensed artwork listed in NOTICES.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/cfmac.app"
VERSION="${VERSION:-2.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
cd "$ROOT"

"$ROOT/scripts/fetch-artwork.sh"

swift build -c release --arch arm64 --product cfmac
swift build -c release --arch arm64 --product cfmac-helper
swift build -c release --arch arm64 --product cfmac-tools
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchServices"
cp "$BIN/cfmac" "$APP/Contents/MacOS/cfmac"
cp "$BIN/cfmac-helper" "$APP/Contents/Library/LaunchServices/cfmac-helper"
# Artwork: planet textures are shown at most ~480 px tall, so 1024 px wide (2:1) is plenty;
# this cuts bundle size and texture memory roughly by four.
rsync -a --exclude '.source-sha256' "$ROOT/Artwork/" "$APP/Contents/Resources/Artwork/"
for texture in "$APP/Contents/Resources/Artwork"/*.jpg "$APP/Contents/Resources/Artwork"/saturn-ring.png; do
  sips --resampleWidth 1024 "$texture" >/dev/null
done
cp "$ROOT/TERMS.md" "$ROOT/NOTICES.md" "$ROOT/PRIVACY.md" "$APP/Contents/Resources/"

ICONSET="$ROOT/build/cfmac.iconset"
rm -rf "$ICONSET"
CFMAC_RESOURCES_DIR="$ROOT" "$BIN/cfmac-tools" icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/cfmac.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>cfmac</string>
  <key>CFBundleIdentifier</key><string>app.cfmac.mac</string>
  <key>CFBundleName</key><string>cfmac</string>
  <key>CFBundleDisplayName</key><string>cfmac</string>
  <key>CFBundleIconFile</key><string>cfmac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 cfmac contributors. All rights reserved. Free software, provided as is.</string>
  <key>NSAppleEventsUsageDescription</key><string>Used during uninstall to ask Finder to move protected apps to the Trash.</string>
  <key>NSDesktopFolderUsageDescription</key><string>When you analyze disk usage, cfmac reads only the names and sizes of files on your Desktop. It never opens them, and nothing leaves your Mac.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>When you analyze disk usage, cfmac reads only the names and sizes of files in Documents. It never opens them, and nothing leaves your Mac.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>When you analyze disk usage, cfmac reads only the names and sizes of files in Downloads. It never opens them, and nothing leaves your Mac.</string>
</dict>
</plist>
PLIST

# Sign inside-out: the helper, then the app that contains it (ad hoc).
# Hardened runtime blocks code injection (DYLD_* variables, unsigned libraries) into both.
codesign --force --options runtime --sign - --identifier app.cfmac.helper "$APP/Contents/Library/LaunchServices/cfmac-helper"
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
