#!/bin/bash
# Renders sample devices only. The binary contains no real audio service.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
OUT=".build/preview/panel.png"
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then OUT="$1"; shift; fi
WORK=".build/preview"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "${PREVIEW_SOURCES[@]}" tools/PreviewMain.swift -o "$WORK/soundpinpreview"
"$WORK/soundpinpreview" "$OUT" "$@"
test -s "$OUT"
echo "Wrote $OUT"
