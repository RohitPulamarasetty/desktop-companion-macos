#!/bin/bash
# Builds a release binary and assembles it into a proper .app bundle.
# This is required (not optional) for UNUserNotificationCenter to work and
# for Bundle.main resource resolution to be reliable -- a bare Mach-O
# executable run directly has no bundle identifier and most notification
# and resource APIs either fail or behave unpredictably without one.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building release..."
swift build -c release

APP_NAME="DesktopCompanion.app"
APP_DIR=".build/${APP_NAME}"
CONTENTS="${APP_DIR}/Contents"

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp .build/release/DesktopCompanionApp "${CONTENTS}/MacOS/DesktopCompanionApp"
cp Sources/App/Info.plist "${CONTENTS}/Info.plist"

# App icon (see docs/RELEASE_CHECKLIST.md -- this is a placeholder icon,
# not final brand art). Optional: only copy if it's been built.
if [ -f "Sources/App/AppIcon.icns" ]; then
  cp "Sources/App/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"
fi

# Character asset packaging is license-gated, not just content-gated.
# See docs/CHARACTER_LICENSING.md for the full rationale: this is a free,
# non-commercial v0.1.0 testing release, and even free redistribution of
# an asset whose redistribution rights are unconfirmed is a real risk
# (redistribution != commercial use). Every character's manifest.json
# always ships (it's just metadata/code, no copyrighted art); a
# character's sprites/sounds/preview only ship if its own manifest
# records an explicit, direct license.commercialUse == true grant. This
# is read from the manifest data at package time -- not a hardcoded name
# list -- so it tracks license changes automatically.
echo "Selecting characters eligible for default asset packaging (see docs/CHARACTER_LICENSING.md)..."
mkdir -p "${CONTENTS}/Resources/Characters"
SHIPPED_ASSET_CHARS=()
SKIPPED_ASSET_CHARS=()
for dir in Characters/*/; do
  id="$(basename "$dir")"
  manifest="${dir}manifest.json"
  [ -f "$manifest" ] || continue
  dest="${CONTENTS}/Resources/Characters/${id}"
  mkdir -p "$dest"
  cp "$manifest" "$dest/manifest.json"

  commercial_use="$(jq -r '.license.commercialUse // false' "$manifest" 2>/dev/null || echo false)"
  if [ "$commercial_use" = "true" ]; then
    # Only what the engine loads (clip strips, preview, pack provenance);
    # never the downloaded zips or full source sheets.
    rsync -a --prune-empty-dirs \
      --include='*/' \
      --include='preview.png' --include='sprites/***' \
      --include='sounds/***' --include='source/pet.json' \
      --exclude='*' \
      "$dir" "$dest/"
    SHIPPED_ASSET_CHARS+=("$id")
  else
    SKIPPED_ASSET_CHARS+=("$id")
  fi
done
echo "  shipping assets for: ${SHIPPED_ASSET_CHARS[*]}"
echo "  metadata-only (no assets packaged): ${#SKIPPED_ASSET_CHARS[@]} characters -- see docs/CHARACTER_LICENSING.md"

echo ""
echo "Verifying bundle..."

fail() { echo "VERIFY FAILED: $1" >&2; exit 1; }

[ -x "${CONTENTS}/MacOS/DesktopCompanionApp" ] || fail "executable missing or not executable"
[ -f "${CONTENTS}/Info.plist" ] || fail "Info.plist missing"
[ -d "${CONTENTS}/Resources/Characters" ] || fail "Resources/Characters missing"

CHAR_COUNT=$(find "${CONTENTS}/Resources/Characters" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
[ "${CHAR_COUNT}" -ge 1 ] || fail "no characters were packaged"
for dir in "${CONTENTS}/Resources/Characters"/*/; do
  [ -f "${dir}manifest.json" ] || fail "$(basename "$dir") is missing manifest.json in the packaged bundle"
done

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${CONTENTS}/Info.plist")
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${CONTENTS}/Info.plist")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${CONTENTS}/Info.plist")
[ -n "${BUNDLE_ID}" ] || fail "CFBundleIdentifier is empty"
[ "${BUNDLE_ID}" != "com.local.desktopcompanion" ] || fail "CFBundleIdentifier is still the placeholder value"

echo "  bundle id:      ${BUNDLE_ID}"
echo "  version:        ${SHORT_VERSION} (build ${BUILD_VERSION})"
echo "  characters:     ${CHAR_COUNT} packaged"

echo "Launch smoke test (3s, then quit)..."
"${CONTENTS}/MacOS/DesktopCompanionApp" >/tmp/dc_package_smoketest.log 2>&1 &
SMOKE_PID=$!
sleep 3
if ! kill -0 "${SMOKE_PID}" 2>/dev/null; then
  cat /tmp/dc_package_smoketest.log >&2
  fail "app exited within 3s of launch -- see log above"
fi
kill "${SMOKE_PID}" 2>/dev/null || true
wait "${SMOKE_PID}" 2>/dev/null || true
echo "  launched and stayed running for 3s, then quit cleanly."

CODESIGN_STATUS="NOT SIGNED"
if codesign -dv "${APP_DIR}" 2>&1 | grep -q "adhoc"; then
  CODESIGN_STATUS="ad-hoc only (arm64's automatic linker signature -- NOT a Developer ID signature)"
elif codesign -dv "${APP_DIR}" >/dev/null 2>&1; then
  CODESIGN_STATUS="signed -- verify identity with 'codesign -dvvv'"
fi

echo ""
echo "================================================================"
echo " Packaged and verified: ${APP_DIR}"
echo " Run with: open '${APP_DIR}'"
echo ""
echo " Code signing:    ${CODESIGN_STATUS}"
echo " Notarization:    NOT DONE (requires an Apple Developer ID + this"
echo "                  machine has no Xcode/signing credentials configured)"
echo ""
echo " This bundle is PREPARED for distribution (correct structure,"
echo " real bundle id, verified resources, launches cleanly) but is NOT"
echo " a signed/notarized release artifact. See docs/RELEASE_CHECKLIST.md"
echo " for exactly what remains before it can ship as a .dmg."
echo "================================================================"
