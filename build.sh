#!/usr/bin/env bash
# Build K-Whisper.app bundle from the SPM executable.
#
# Usage: ./build.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="KWhisper"
BUNDLE_NAME="K-Whisper"
APP_DIR="$ROOT/build/$BUNDLE_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "▶︎ Building K-Whisper ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)
EXE="$BIN_PATH/$APP"

if [[ ! -x "$EXE" ]]; then
    echo "❌ Built executable not found at $EXE"
    exit 1
fi

echo "▶︎ Rendering AppIcon.icns…"
ICON_TMP="$ROOT/build/iconset"
rm -rf "$ICON_TMP"
"$EXE" --render-iconset "$ICON_TMP.iconset" >/dev/null
iconutil -c icns -o "$ROOT/build/AppIcon.icns" "$ICON_TMP.iconset"
rm -rf "$ICON_TMP.iconset"

echo "▶︎ Assembling app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$EXE" "$BIN_DIR/$APP"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/build/AppIcon.icns" "$RES_DIR/AppIcon.icns"

# Ad-hoc sign so the OS lets you launch it (without an Apple Developer ID).
echo "▶︎ Ad-hoc codesigning…"
codesign --force --deep --sign - --entitlements "$ROOT/Resources/KWhisper.entitlements" "$APP_DIR"

# Tell Finder/Dock to refresh icon caches for this bundle.
touch "$APP_DIR"

echo "✅ Built $APP_DIR"
echo
echo "Run with:    open \"$APP_DIR\""
echo "Or directly: \"$BIN_DIR/$APP\""
