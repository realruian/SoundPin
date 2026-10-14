#!/bin/bash
# Checks settings logic in memory; never writes to any preferences domain.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/settings-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -module-cache-path "$WORK/ModuleCache" \
  "${MODEL_SOURCES[@]}" SoundPin/Services/PriorityManager.swift \
  tools/AudioTestSupport.swift tools/SettingsCheckMain.swift -o "$WORK/check"
"$WORK/check"
