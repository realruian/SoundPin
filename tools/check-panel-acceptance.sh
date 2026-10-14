#!/bin/bash
# Opens a temporary real MenuBarExtra with the production panel and simulated audio.
# Requires Accessibility and Screen Recording. Never changes system preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/check-sources.sh
WORK=".build/panel-acceptance"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "${PREVIEW_SOURCES[@]}" tools/PanelAcceptanceMain.swift -o "$WORK/panel"
swiftc -warnings-as-errors -module-cache-path "$WORK/ModuleCache" tools/PanelAcceptanceDriver.swift -o "$WORK/driver"
mkdir -p "$WORK/SoundPinAcceptance.app/Contents/MacOS"
cp "$WORK/panel" "$WORK/SoundPinAcceptance.app/Contents/MacOS/SoundPinAcceptance"
cat > "$WORK/SoundPinAcceptance.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SoundPinAcceptance</string>
<key>CFBundleIdentifier</key><string>io.github.realruian.SoundPin.Acceptance</string>
<key>CFBundleName</key><string>SoundPinAcceptance</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
"$WORK/SoundPinAcceptance.app/Contents/MacOS/SoundPinAcceptance" "$@" &
PANEL_PID=$!
trap 'kill "$PANEL_PID" 2>/dev/null || true; wait "$PANEL_PID" 2>/dev/null || true' EXIT
"$WORK/driver" "$PANEL_PID" "$WORK/run-$(date +%Y%m%d-%H%M%S)${1:-normal}" "$@"
