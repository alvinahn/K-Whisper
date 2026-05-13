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

# A stable signing identity keeps macOS Accessibility grants across rebuilds.
# Without one, ad-hoc signing changes the app's code identity every build and TCC
# quite reasonably asks the user to grant Accessibility again.
SIGN_IDENTITY="${KWHISPER_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F '"' '/Developer ID Application|Apple Development|K-Whisper Local/ { print $2; exit }'
    )"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "▶︎ Codesigning with identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ROOT/Resources/KWhisper.entitlements" "$APP_DIR"
else
    echo "▶︎ Ad-hoc codesigning…"
    echo "   No stable code-signing identity found; Accessibility will need re-granting after rebuilds."
    echo "   Set KWHISPER_CODESIGN_IDENTITY to a local Code Signing certificate to keep TCC grants stable."
    codesign --force --deep --sign - --entitlements "$ROOT/Resources/KWhisper.entitlements" "$APP_DIR"
fi

# Tell Finder/Dock to refresh icon caches for this bundle.
touch "$APP_DIR"

echo "✅ Built $APP_DIR"
echo
echo "Run with:    open \"$APP_DIR\""
echo "Or directly: \"$BIN_DIR/$APP\""
