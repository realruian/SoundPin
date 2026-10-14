#!/bin/bash
# Deterministic routing checks: in-memory devices/settings and a virtual clock.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/routing-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$WORK/ModuleCache" "${MANAGER_SOURCES[@]}" \
  tools/AudioTestSupport.swift tools/RoutingCheckMain.swift -o "$WORK/check"
"$WORK/check"
