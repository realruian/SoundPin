#!/bin/bash
# Builds the app and installs it with a backup and rollback on failure.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SoundPin"
DERIVED=".build"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "Building $APP_NAME..."
mkdir -p "$DERIVED"
# Signed "to run locally": enough for this Mac, and macOS does not block a local build
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build > "$DERIVED/build.log" 2>&1; then
  grep -E "error:" "$DERIVED/build.log" || tail -20 "$DERIVED/build.log"
  echo "Build failed. Full log: $DERIVED/build.log"
  exit 1
fi

bash tools/install-app.sh "$BUILT"
