#!/bin/bash
# Production layout in hidden windows, simulated audio only. No UI or system setting changes.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/panel-layout-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "${PREVIEW_SOURCES[@]}" tools/PanelLayoutCheckMain.swift -o "$WORK/check"
"$WORK/check"
