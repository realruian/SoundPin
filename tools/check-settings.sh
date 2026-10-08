#!/bin/bash
# Checks how devices are remembered and marked "never select automatically", including
# a device with one UID for its microphone and its speaker. Uses a settings domain of
# its own and does not touch the audio devices.
#   tools/check-settings.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/settings-check"
mkdir -p "$WORK/src"
cp SoundPin/Models/*.swift SoundPin/Services/PriorityManager.swift "$WORK/src/"
cp tools/SettingsCheckMain.swift "$WORK/src/"
swiftc -suppress-warnings -parse-as-library -o "$WORK/soundpinsettingscheck" "$WORK"/src/*.swift

# The settings domain is named after the executable; removed again on exit
trap 'sleep 1; defaults delete soundpinsettingscheck >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/soundpinsettingscheck.plist"' EXIT
defaults delete soundpinsettingscheck >/dev/null 2>&1 || true

"$WORK/soundpinsettingscheck"
