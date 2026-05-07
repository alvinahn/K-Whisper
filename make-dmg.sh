#!/usr/bin/env bash
# Build a distributable K-Whisper.dmg from build/K-Whisper.app.
#
# Usage: ./make-dmg.sh
#
# The DMG opens with K-Whisper.app on the left and an Applications shortcut
# on the right — drag to install, the standard macOS pattern.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="K-Whisper"
APP_PATH="$ROOT/build/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ $APP_NAME.app not found at $APP_PATH"
    echo "   Run ./build.sh first."
    exit 1
fi

# Read version from the bundled Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$ROOT/build/$DMG_NAME"
STAGE="$ROOT/build/dmg-stage"

# Build a staging folder with the app + Applications symlink
echo "▶︎ Staging at $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Create the DMG (UDZO = bzip2-style compressed, read-only — standard for distribution)
echo "▶︎ Creating $DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

# Ad-hoc sign the DMG too (won't matter for unsigned-app distribution but is harmless).
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true

# Cleanup staging
rm -rf "$STAGE"

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo
echo "✅ $DMG_PATH ($SIZE)"
echo
echo "Share this DMG with anyone on macOS. They open it, drag K-Whisper.app to"
echo "Applications, then right-click → Open the first time (because it's unsigned)."
