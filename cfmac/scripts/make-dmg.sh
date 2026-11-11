#!/bin/bash
# Packages build/cfmac.app into build/cfmac-<version>.dmg with an Applications shortcut,
# the Terms of Use and the open source notices. Builds the app first if needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/cfmac.app"
[[ -d "$APP" ]] || "$ROOT/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/cfmac-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/cfmac.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/TERMS.md" "$STAGE/Terms of Use.md"
cp "$ROOT/NOTICES.md" "$STAGE/Open Source Licenses.md"
cp "$ROOT/PRIVACY.md" "$STAGE/Privacy Statement.md"

rm -f "$DMG"
hdiutil create -volname "cfmac $VERSION" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" >/dev/null
codesign --force --sign - "$DMG"
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG"
