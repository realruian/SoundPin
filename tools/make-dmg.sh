#!/bin/bash
# Builds a universal release build and packs it into a disk image under dist/.
#   tools/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SoundPin"
DERIVED=".build/release"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "Building $APP_NAME (arm64 + x86_64)..."
mkdir -p "$DERIVED"
# Signed "to run locally": there is no Developer ID, so the image is not notarized
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build > "$DERIVED/build.log" 2>&1; then
  grep -E "error:" "$DERIVED/build.log" || tail -20 "$DERIVED/build.log"
  echo "Build failed. Full log: $DERIVED/build.log"
  exit 1
fi
codesign --verify --deep --strict "$BUILT"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT/Contents/Info.plist")
DMG="dist/$APP_NAME-$VERSION.dmg"
STAGE="$DERIVED/dmg"

echo "Packing $DMG..."
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" dist
ditto "$BUILT" "$STAGE/$APP_NAME.app"
# Lets the user drag the app onto Applications inside the image
ln -s /Applications "$STAGE/Applications"
# hdiutil prints a deprecation notice on newer macOS; it goes to a log unless the command fails
if ! hdiutil create -volname "SoundPin" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > "$DERIVED/hdiutil.log" 2>&1; then
  cat "$DERIVED/hdiutil.log"
  exit 1
fi

echo ""
echo "Wrote $DMG ($(lipo -archs "$BUILT/Contents/MacOS/$APP_NAME"))"
shasum -a 256 "$DMG"
