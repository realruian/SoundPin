#!/bin/bash
# Sample classification and symbol checks. No audio service or manager is linked.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/scenario"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -module-cache-path "$WORK/ModuleCache" \
  "${MODEL_SOURCES[@]}" SoundPin/Services/PriorityManager.swift tools/AudioTestSupport.swift \
  tools/ScenarioMain.swift -o "$WORK/check"
"$WORK/check" "$@"
