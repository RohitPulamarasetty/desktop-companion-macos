#!/bin/bash
# Builds a universal (arm64 + x86_64) release binary and assembles
# release/DesktopCompanion.app. Ad-hoc signed (no Developer ID is used).
# Only characters' manifests, sprites and previews go into the bundle.
# Set INCLUDE_LOCAL_CHARACTERS=1 to also bundle ./LocalCharacters (for a
# personal build that is never redistributed).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="release/Desktop Companion.app"
CONTENTS="${APP}/Contents"
MIN_MACOS="13.0"

echo "Building release binaries..."
swift build -c release --triple "arm64-apple-macosx${MIN_MACOS}" >/dev/null
swift build -c release --triple "x86_64-apple-macosx${MIN_MACOS}" >/dev/null

rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources/Characters"
lipo -create \
  ".build/arm64-apple-macosx/release/DesktopCompanionApp" \
  ".build/x86_64-apple-macosx/release/DesktopCompanionApp" \
  -output "${CONTENTS}/MacOS/DesktopCompanionApp"
cp Sources/App/Info.plist "${CONTENTS}/Info.plist"
cp Sources/App/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"

SOURCES=(Characters)
if [ "${INCLUDE_LOCAL_CHARACTERS:-0}" = "1" ] && [ -d LocalCharacters ]; then SOURCES+=(LocalCharacters); fi
for src in "${SOURCES[@]}"; do
  for dir in "${src}"/*/; do
    [ -f "${dir}manifest.json" ] || continue
    dest="${CONTENTS}/Resources/Characters/$(basename "${dir}")"
    mkdir -p "${dest}"
    rsync -a --prune-empty-dirs --include='*/' --include='manifest.json' --include='preview.png' \
      --include='sprites/***' --exclude='*' "${dir}" "${dest}/"
  done
done
cp LICENSE THIRD_PARTY.md "${CONTENTS}/Resources/"

codesign --force --deep --sign - "${APP}"

echo "Verifying bundle..."
fail() { echo "VERIFY FAILED: $1" >&2; exit 1; }
[ -x "${CONTENTS}/MacOS/DesktopCompanionApp" ] || fail "executable missing"
lipo -info "${CONTENTS}/MacOS/DesktopCompanionApp" | grep -q "x86_64" || fail "x86_64 slice missing"
lipo -info "${CONTENTS}/MacOS/DesktopCompanionApp" | grep -q "arm64" || fail "arm64 slice missing"
codesign --verify --deep --strict "${APP}" || fail "code signature invalid"
COUNT=$(find "${CONTENTS}/Resources/Characters" -name manifest.json | wc -l | tr -d ' ')
[ "${COUNT}" -ge 1 ] || fail "no characters packaged"
echo "  $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${CONTENTS}/Info.plist") $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS}/Info.plist"), ${COUNT} characters"
echo "  $(du -sh "${APP}" | cut -f1) on disk"
echo "Built ${APP}"
