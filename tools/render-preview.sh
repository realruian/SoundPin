#!/bin/bash
# Renders the panel to a PNG without opening it, for checking layout changes.
#   tools/render-preview.sh [output.png] [--manual-look] [--edit-look] [--demo] [--lang en|zh-Hans]
#
# Does not change the audio devices: the preview process reads a copy of the
# app's settings with automatic switching turned off.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=".build/preview/panel.png"
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  OUT="$1"
  shift
fi

WORK=".build/preview"
mkdir -p "$WORK/src"
cp AudioPriorityBar/Models/*.swift AudioPriorityBar/Services/*.swift AudioPriorityBar/Views/*.swift "$WORK/src/"
# The app's own entry point has to go, the preview brings its own
sed 's/^@main$//' AudioPriorityBar/AudioPriorityBarApp.swift > "$WORK/src/AudioPriorityBarApp.swift"
cp tools/PreviewMain.swift "$WORK/src/"
swiftc -suppress-warnings -parse-as-library -o "$WORK/apbpreview" "$WORK"/src/*.swift

# The preview's settings domain is named after its executable
# Removed again on exit; the pause lets the preview's last settings write land first
trap 'sleep 1; defaults delete apbpreview >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/apbpreview.plist"' EXIT
if defaults export app.audioprioritybar "$WORK/settings.plist" 2>/dev/null; then
  defaults import apbpreview "$WORK/settings.plist"
fi
defaults write apbpreview customMode -bool true

"$WORK/apbpreview" "$OUT" "$@"
echo "Wrote $OUT"
