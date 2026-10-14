#!/bin/bash
# Request state and bounded recovery, without linking the real listening-mode service.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/listening-mode-request-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$WORK/ModuleCache" "${MANAGER_SOURCES[@]}" \
  tools/AudioTestSupport.swift tools/ListeningModeRequestCheckMain.swift -o "$WORK/check"
"$WORK/check"
