#!/bin/bash
# Builds release/DesktopCompanion-v<version>-macOS.dmg from release/Desktop Companion.app:
# the app and an Applications shortcut, laid out side by side.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="release/Desktop Companion.app"
[ -d "${APP}" ] || ./scripts/package_app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")
DMG="release/DesktopCompanion-v${VERSION}-macOS.dmg"
RW="release/rw.dmg"
VOL="Desktop Companion"
STAGE="release/dmg_stage"

rm -rf "${STAGE}" "${DMG}" "${RW}"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

hdiutil create -volname "${VOL}" -srcfolder "${STAGE}" -fs HFS+ -format UDRW -ov "${RW}" >/dev/null
rm -rf "${STAGE}"

# Lay the window out (icon positions). This talks to Finder; if
# Finder scripting isn't allowed the DMG is still complete, just unstyled.
DEVICE=$(hdiutil attach "${RW}" -nobrowse -noverify -noautoopen | grep -E '^/dev/' | head -1 | awk '{print $1}')
sleep 1
osascript <<OSA || echo "  (Finder styling skipped)" >&2
tell application "Finder"
  tell disk "${VOL}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 420}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set position of item "Desktop Companion.app" of container window to {150, 150}
    set position of item "Applications" of container window to {410, 150}
    update without registering applications
    delay 2
    close
    open
    delay 2
    close
  end tell
end tell
OSA
sync
sleep 3
hdiutil detach "${DEVICE}" >/dev/null
hdiutil convert "${RW}" -format UDZO -imagekey zlib-level=9 -o "${DMG}" >/dev/null
rm -f "${RW}"

echo "Verifying DMG..."
MOUNT=$(hdiutil attach "${DMG}" -nobrowse -readonly | grep -E '/Volumes/' | sed 's/.*\(\/Volumes\/.*\)$/\1/')
fail() { hdiutil detach "${MOUNT}" >/dev/null 2>&1 || true; echo "VERIFY FAILED: $1" >&2; exit 1; }
[ -d "${MOUNT}/Desktop Companion.app" ] || fail "app missing"
[ -L "${MOUNT}/Applications" ] || fail "Applications shortcut missing"
codesign --verify --deep --strict "${MOUNT}/Desktop Companion.app" || fail "signature invalid inside the DMG"
hdiutil detach "${MOUNT}" >/dev/null
echo "Built ${DMG} ($(du -h "${DMG}" | cut -f1))"
shasum -a 256 "${DMG}"
