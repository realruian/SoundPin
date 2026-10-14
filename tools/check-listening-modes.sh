#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=".build/listening-mode-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -module-cache-path "$WORK/ModuleCache" \
  SoundPin/Models/AudioServices.swift SoundPin/Models/AudioDevice.swift SoundPin/Models/ListeningMode.swift \
  SoundPin/Models/Localization.swift SoundPin/Services/ListeningModeService.swift \
  tools/ListeningModeCheckMain.swift -o "$WORK/check"
"$WORK/check"
