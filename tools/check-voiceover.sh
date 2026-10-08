#!/bin/bash
# Prints what VoiceOver finds in the panel and runs one row action, without turning
# VoiceOver on. The panel is shown with sample devices in an invisible window, in a
# process with its own settings and automatic switching off, so the audio devices are
# not touched. The terminal needs Accessibility permission.
#   tools/check-voiceover.sh [--lang en|zh-Hans]
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/voiceover-check"
mkdir -p "$WORK/src"
cp SoundPin/Models/*.swift SoundPin/Services/*.swift SoundPin/Views/*.swift "$WORK/src/"
# The app's own entry point has to go, the check brings its own
sed 's/^@main$//' SoundPin/SoundPinApp.swift > "$WORK/src/SoundPinApp.swift"
cp tools/VoiceOverPanelMain.swift "$WORK/src/"
swiftc -suppress-warnings -parse-as-library -o "$WORK/soundpinvoiceover" "$WORK"/src/*.swift
swiftc -suppress-warnings -o "$WORK/voiceoverdump" tools/VoiceOverDump.swift

# The panel's settings domain is named after its executable; removed again on exit
trap 'kill "$PANEL" >/dev/null 2>&1 || true; wait "$PANEL" 2>/dev/null || true; sleep 1; defaults delete soundpinvoiceover >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/soundpinvoiceover.plist"' EXIT
defaults write soundpinvoiceover customMode -bool true

"$WORK/soundpinvoiceover" 10 "$@" &
PANEL=$!
sleep 3

# The action names follow the panel's language
if [[ " $* " == *" zh-Hans "* ]]; then
  "$WORK/voiceoverdump" "$PANEL" "Studio Display Speakers" "上移" "上移"
else
  "$WORK/voiceoverdump" "$PANEL" "Studio Display Speakers" "Move Up" "Move Up"
fi
