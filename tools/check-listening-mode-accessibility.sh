#!/bin/bash
# Verifies mode button actions, pending state, timeout and retry through AX.
# Uses simulated services in an invisible window; requires Accessibility permission.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/listening-mode-ax-check"
mkdir -p "$WORK"
source tools/check-sources.sh
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "${PREVIEW_SOURCES[@]}" tools/VoiceOverPanelMain.swift -o "$WORK/soundpinvoiceover"
swiftc -warnings-as-errors -o "$WORK/voiceoverdump" tools/ListeningModeAXCheck.swift
PANEL=""
trap 'if [ -n "$PANEL" ]; then kill "$PANEL" >/dev/null 2>&1 || true; wait "$PANEL" 2>/dev/null || true; fi' EXIT

"$WORK/soundpinvoiceover" 20 --listening-ax --lang en &
PANEL=$!
sleep 3

"$WORK/voiceoverdump" "$PANEL"
