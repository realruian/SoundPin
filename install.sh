#!/bin/bash
# Builds the app and installs it to /Applications, replacing the running copy.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AudioPriorityBar"
DERIVED=".build"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

echo "Building $APP_NAME..."
mkdir -p "$DERIVED"
# Signed "to run locally": enough for this Mac, and macOS does not block a local build
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build > "$DERIVED/build.log" 2>&1; then
  grep -E "error:" "$DERIVED/build.log" || tail -20 "$DERIVED/build.log"
  echo "Build failed. Full log: $DERIVED/build.log"
  exit 1
fi

echo "Installing to $DEST..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
codesign --verify --deep --strict "$DEST"
open "$DEST"

echo ""
echo "Installed and launched: $DEST"
