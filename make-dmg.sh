#!/usr/bin/env bash
# Build a distributable K-Whisper.dmg with the standard
# "drag the app onto the Applications folder" installer layout.
#
# Pipeline:
#  1. Render background.png via the K-Whisper binary (--render-dmg-background)
#  2. Stage the app + Applications symlink + .background folder
#  3. Create writable DMG, mount it, run AppleScript to set window/bg/icon positions
#  4. Detach and convert to compressed read-only DMG (UDZO)
#
# Output: build/K-Whisper-{version}.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="K-Whisper"
APP_PATH="$ROOT/build/$APP_NAME.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/KWhisper"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ $APP_NAME.app not found at $APP_PATH"
    echo "   Run ./build.sh first."
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_NAME="$APP_NAME-$VERSION.dmg"
FINAL_DMG="$ROOT/build/$DMG_NAME"
RW_DMG="$ROOT/build/$APP_NAME-rw.dmg"
STAGE="$ROOT/build/dmg-stage"
VOLUME_NAME="$APP_NAME"

# 1. Render background PNG using the app binary
BG_DIR="$STAGE/.background"
BG_PNG="$BG_DIR/background.png"
echo "▶︎ Rendering background.png"
rm -rf "$STAGE"
mkdir -p "$BG_DIR"
"$EXECUTABLE" --render-dmg-background "$BG_PNG" >/dev/null

# 2. Stage app + Applications symlink
echo "▶︎ Staging app + Applications symlink"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 3. Create writable DMG
echo "▶︎ Creating writable DMG"
rm -f "$RW_DMG" "$FINAL_DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    "$RW_DMG" >/dev/null

# Mount it. We grep for the device node so we can detach precisely later.
echo "▶︎ Mounting and configuring window"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | grep -E '^/dev/' \
    | head -n 1 \
    | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# Wait briefly for Finder to register the volume
sleep 1

# 4. AppleScript: window size, icon view, bg image, icon positions
osascript <<APPLESCRIPT
on run
    tell application "Finder"
        tell disk "$VOLUME_NAME"
            open
            delay 0.6
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set sidebar width of container window to 0
            set the bounds of container window to {200, 200, 740, 580}

            set viewOpts to icon view options of container window
            set arrangement of viewOpts to not arranged
            set icon size of viewOpts to 96
            set text size of viewOpts to 12

            -- POSIX file path then coerce to alias — robust across macOS versions.
            set bgFile to POSIX file "$MOUNT_POINT/.background/background.png" as alias
            set background picture of viewOpts to bgFile

            -- AppleScript icon positions are CENTER points, measured from window's top-left.
            set position of item "$APP_NAME.app" of container window to {140, 200}
            set position of item "Applications" of container window to {400, 200}

            delay 0.4
            update without registering applications
            delay 0.6
            close
        end tell
    end tell
end run
APPLESCRIPT

# Hide the .background folder (HFS hidden flag)
chflags hidden "$MOUNT_POINT/.background"

# Wait for Finder to commit .DS_Store
sync
sleep 1

# 5. Detach
echo "▶︎ Detaching"
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force >/dev/null

# 6. Convert to compressed read-only DMG (UDZO)
echo "▶︎ Compressing → $DMG_NAME"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

# Ad-hoc sign for cleanliness (won't matter for unsigned-app distribution but harmless)
codesign --force --sign - "$FINAL_DMG" 2>/dev/null || true

# Cleanup
rm -f "$RW_DMG"
rm -rf "$STAGE"

SIZE=$(du -h "$FINAL_DMG" | cut -f1)
echo
echo "✅ $FINAL_DMG ($SIZE)"
echo
echo "Opens with the standard drag-to-Applications installer layout."
