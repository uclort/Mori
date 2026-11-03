#!/usr/bin/env bash
# Builds an unsigned Mori .ipa (for AltStore / SideStore / TrollStore sideloading).
#
#   ios/build-ipa.sh [output-name]
#
# Output: dist/<output-name>.ipa  (default: Mori-v<MARKETING_VERSION>-iOS-Unsigned)
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
BUILD_DIR="$ROOT/build/ios"

if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcodebuild -version >/dev/null 2>&1; then
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)"
  [[ -n "$XCODE_APP" ]] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

# Keep the Xcode project in sync with project.yml when XcodeGen is available
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
fi

VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
NAME="${1:-Mori-v${VERSION}-iOS-Unsigned}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
LOG="$BUILD_DIR/xcodebuild.log"
echo "Archiving Mori $VERSION (log: $LOG)…"
if ! xcodebuild \
  -project Mori.xcodeproj \
  -scheme Mori \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$BUILD_DIR/Mori.xcarchive" \
  archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" >"$LOG" 2>&1; then
  grep -E "error:|BUILD|ARCHIVE" "$LOG" | tail -30 >&2
  exit 1
fi

APP="$BUILD_DIR/Mori.xcarchive/Products/Applications/Mori.app"
if [[ ! -d "$APP" ]]; then
  echo "Archive failed: $APP not found" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR/Payload" "$ROOT/dist"
cp -R "$APP" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && rm -f "$ROOT/dist/$NAME.ipa" && zip -qry "$ROOT/dist/$NAME.ipa" Payload)
rm -rf "$BUILD_DIR"

echo "✅ $ROOT/dist/$NAME.ipa"
