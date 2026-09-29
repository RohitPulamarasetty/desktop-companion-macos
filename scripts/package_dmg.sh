#!/bin/bash
# Builds a .dmg from the packaged .app produced by scripts/package_app.sh.
# Uses hdiutil (built into macOS) -- no third-party tooling required.
#
# This produces a real, mountable .dmg for local testing/distribution. It
# does NOT sign or notarize anything -- see docs/RELEASE_CHECKLIST.md for
# what's still a manual step requiring an Apple Developer ID this build
# machine does not have.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DesktopCompanion.app"
APP_DIR=".build/${APP_NAME}"

if [ ! -d "${APP_DIR}" ]; then
  echo "No packaged app found at ${APP_DIR} -- running package_app.sh first..."
  ./scripts/package_app.sh
fi

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_DIR}/Contents/Info.plist")
DMG_NAME="DesktopCompanion-${SHORT_VERSION}.dmg"
DMG_PATH=".build/${DMG_NAME}"
STAGE_DIR=".build/dmg_stage"

echo ""
echo "Building ${DMG_NAME}..."
rm -rf "${STAGE_DIR}" "${DMG_PATH}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_DIR}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

hdiutil create -volname "Desktop Companion ${SHORT_VERSION}" \
  -srcfolder "${STAGE_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

rm -rf "${STAGE_DIR}"

echo ""
echo "Smoke-testing the .dmg (attach, verify contents, detach)..."
MOUNT_OUTPUT=$(hdiutil attach "${DMG_PATH}" -nobrowse -readonly)
MOUNT_POINT=$(echo "${MOUNT_OUTPUT}" | grep -E '/Volumes/' | awk -F'\t' '{print $NF}' | tail -1)

fail() {
  hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  echo "VERIFY FAILED: $1" >&2
  exit 1
}

[ -n "${MOUNT_POINT}" ] || fail "could not determine mount point from hdiutil attach output"
[ -d "${MOUNT_POINT}/${APP_NAME}" ] || fail "${APP_NAME} not found on mounted volume"
[ -L "${MOUNT_POINT}/Applications" ] || fail "Applications symlink not found on mounted volume"

hdiutil detach "${MOUNT_POINT}" >/dev/null
echo "  mounted, verified contents (${APP_NAME} + Applications symlink), detached cleanly."

echo ""
echo "================================================================"
echo " Built and verified: ${DMG_PATH}"
echo ""
echo " This .dmg is UNSIGNED and NOT NOTARIZED. Gatekeeper will warn or"
echo " block on any Mac other than this build machine. See"
echo " docs/RELEASE_CHECKLIST.md for the remaining signing/notarization"
echo " steps, which require an Apple Developer ID this environment does"
echo " not have."
echo "================================================================"
