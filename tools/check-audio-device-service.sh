#!/bin/bash
# Production HAL boundary, listener recovery, channel mute and renamed-device checks.
# Every HAL operation is injected; no real device reads, registrations or writes.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=".build/audio-device-service-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  SoundPin/Models/*.swift SoundPin/Services/AudioDeviceService.swift tools/AudioDeviceServiceCheckMain.swift -o "$WORK/check"
"$WORK/check"
