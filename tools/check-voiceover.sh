#!/bin/bash
# Prints what VoiceOver finds in the panel and runs one row action, without turning
# VoiceOver on. The panel is shown with sample devices in an invisible window, in a
# process with in-memory settings and simulated audio; real audio services are not linked. The terminal needs Accessibility permission.
#   tools/check-voiceover.sh [--lang en|zh-Hans]
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/voiceover-check"
mkdir -p "$WORK"
source tools/check-sources.sh
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "${PREVIEW_SOURCES[@]}" tools/VoiceOverPanelMain.swift -o "$WORK/soundpinvoiceover"
swiftc -warnings-as-errors -o "$WORK/voiceoverdump" tools/VoiceOverDump.swift
PANEL=""
trap 'if [ -n "$PANEL" ]; then kill "$PANEL" >/dev/null 2>&1 || true; wait "$PANEL" 2>/dev/null || true; fi' EXIT

"$WORK/soundpinvoiceover" 10 "$@" &
PANEL=$!
sleep 3

# The action names follow the panel's language
if [[ " $* " == *" zh-Hans "* ]]; then
  "$WORK/voiceoverdump" "$PANEL" "Studio Display Speakers" "上移" "上移"
else
  "$WORK/voiceoverdump" "$PANEL" "Studio Display Speakers" "Move Up" "Move Up"
fi
