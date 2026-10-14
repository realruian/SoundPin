#!/bin/bash
# Parser, identity, cache, reconnection and subprocess timeout checks. No audio writes.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/battery-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "${MANAGER_SOURCES[@]}" SoundPin/Services/BluetoothBatteryService.swift tools/AudioTestSupport.swift tools/BatteryCheckMain.swift -o "$WORK/check"
"$WORK/check" "$@"
