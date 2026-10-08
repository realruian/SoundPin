#!/bin/bash
# Checks that several device notifications in a row are handled once. Creates and removes
# private test devices that only this process sees; the default devices are not changed.
#   tools/check-events.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/events-check"
mkdir -p "$WORK/src"
cp SoundPin/Models/*.swift SoundPin/Services/AudioDeviceService.swift "$WORK/src/"
cp tools/EventsCheckMain.swift "$WORK/src/"
swiftc -suppress-warnings -parse-as-library -o "$WORK/soundpineventscheck" "$WORK"/src/*.swift

"$WORK/soundpineventscheck"
