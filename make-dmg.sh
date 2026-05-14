#!/usr/bin/env bash
# Build a distributable K-Whisper.dmg with the standard
# "drag the app onto the Applications folder" installer layout.
#
# Pipeline:
#  1. Render background.png via the K-Whisper binary (--render-dmg-background)
#  2. Stage the app + .background folder
#  3. Create writable DMG, mount it
#  4. Make a real Finder alias to /Applications inside the volume
#     (a `ln -s` symlink shows up as an empty icon — Finder doesn't fetch
#      the system folder's icon for symlinks. A real alias does.)
#  5. AppleScript to set window/bg/icon positions
#  6. Detach and convert to compressed read-only DMG (UDZO)
#  7. Copy the K-Whisper app icon onto the final .dmg file
#
# Output: build/K-Whisper-{version}.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="K-Whisper"
APP_PATH="$ROOT/build/$APP_NAME.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/KWhisper"
APP_ALIAS_NAME="Applications"

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

# Finder addresses mounted volumes by display name, so a previously opened
# installer with the same name can make AppleScript configure the wrong disk.
find /Volumes -maxdepth 1 \( -name "$VOLUME_NAME" -o -name "$VOLUME_NAME [0-9]*" \) -type d -print 2>/dev/null \
    | sort -r \
    | while IFS= read -r mountPath; do
        echo "▶︎ Detaching existing installer volume at $mountPath"
        hdiutil detach "$mountPath" -quiet || hdiutil detach "$mountPath" -force -quiet || true
    done

# 1. Render background PNG using the app binary
BG_DIR="$STAGE/.background"
BG_PNG="$BG_DIR/background.png"
echo "▶︎ Rendering background.png"
rm -rf "$STAGE"
mkdir -p "$BG_DIR"
"$EXECUTABLE" --render-dmg-background "$BG_PNG" >/dev/null

# 2. Stage app + .background only — Applications alias is created post-mount
echo "▶︎ Staging app + background"
cp -R "$APP_PATH" "$STAGE/"

# 3. Create writable DMG (with extra free space for the alias we'll create)
echo "▶︎ Creating writable DMG"
rm -f "$RW_DMG" "$FINAL_DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size 30m \
    "$RW_DMG" >/dev/null

# 4. Mount
echo "▶︎ Mounting and configuring window"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | grep -E '^/dev/' \
    | head -n 1 \
    | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

sleep 1

# 5. Create a *real Finder alias* (not a symlink) to /Applications inside the volume
#    so that the icon shows the real Applications-folder appearance instead of an empty box.
osascript <<MAKE_ALIAS
tell application "Finder"
    set appsFolder to (path to applications folder from local domain) as alias
    tell disk "$VOLUME_NAME"
        make new alias file at it to appsFolder with properties {name:"$APP_ALIAS_NAME"}
    end tell
end tell
MAKE_ALIAS

sleep 0.5

# Force-attach the system Applications folder icon onto the alias. Without this,
# the alias often shows up as an empty rounded box because Finder doesn't always
# resolve and cache the target's icon resource on first render.
echo "▶︎ Copying system Applications icon"
"$EXECUTABLE" --copy-icon "/Applications" "$MOUNT_POINT/$APP_ALIAS_NAME" || true
sleep 0.3

# 6. AppleScript: window size, icon view, bg image, icon positions
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
            set text size of viewOpts to 10
            set color of viewOpts to {0, 0, 0}

            set bgFile to POSIX file "$MOUNT_POINT/.background/background.png" as alias
            set background picture of viewOpts to bgFile

            set position of item "$APP_NAME.app" of container window to {140, 200}
            set position of item "$APP_ALIAS_NAME" of container window to {400, 200}

            delay 0.4
            update without registering applications
            delay 0.6
            close
        end tell
    end tell
end run
APPLESCRIPT

# Hide .background from default view
chflags hidden "$MOUNT_POINT/.background"

# Wait for Finder to flush .DS_Store
sync
sleep 1

# 7. Detach
echo "▶︎ Detaching"
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force >/dev/null

# 8. Compress
echo "▶︎ Compressing → $DMG_NAME"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

echo "▶︎ Copying K-Whisper icon onto DMG file"
"$EXECUTABLE" --copy-icon "$APP_PATH" "$FINAL_DMG" || true

codesign --force --sign - "$FINAL_DMG" 2>/dev/null || true

rm -f "$RW_DMG"
rm -rf "$STAGE"

SIZE=$(du -h "$FINAL_DMG" | cut -f1)
echo
echo "✅ $FINAL_DMG ($SIZE)"
echo
echo "Opens with the standard drag-to-Applications installer layout."
