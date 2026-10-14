#!/bin/bash
# Identity reordering and active audio state, using only in-memory services.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/interaction-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$WORK/ModuleCache" "${MANAGER_SOURCES[@]}" \
  tools/AudioTestSupport.swift tools/InteractionCheckMain.swift -o "$WORK/check"
"$WORK/check"
