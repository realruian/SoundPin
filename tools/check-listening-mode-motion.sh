#!/bin/bash
# Opens a temporary, inert MenuBarExtra for four seconds. No AudioManager or
# audio service is created. Requires accessibility permission for System Events.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=".build/listening-mode-motion-check"
mkdir -p "$WORK/src"
cp SoundPin/Models/*.swift SoundPin/Services/*.swift SoundPin/Views/*.swift "$WORK/src/"
sed 's/^@main$//' SoundPin/SoundPinApp.swift > "$WORK/src/SoundPinApp.swift"
cp tools/ListeningModeMotionCheckMain.swift "$WORK/src/"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" -module-cache-path "$WORK/ModuleCache" \
  "$WORK"/src/*.swift -o "$WORK/check"
cat > "$WORK/ClickProbe.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let point = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
let source = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.06)
CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
SWIFT
swiftc "$WORK/ClickProbe.swift" -o "$WORK/click-probe"
mkdir -p "$WORK/SoundPinMotionCheck.app/Contents/MacOS"
cp "$WORK/check" "$WORK/SoundPinMotionCheck.app/Contents/MacOS/SoundPinMotionCheck"
cat > "$WORK/SoundPinMotionCheck.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SoundPinMotionCheck</string>
<key>CFBundleIdentifier</key><string>io.github.realruian.SoundPin.MotionCheck</string>
<key>CFBundleName</key><string>SoundPinMotionCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
"$WORK/SoundPinMotionCheck.app/Contents/MacOS/SoundPinMotionCheck" &
MOTION_CHECK_PID=$!
trap 'kill "$MOTION_CHECK_PID" 2>/dev/null || true' EXIT
sleep 0.7
MOTION_POINT=$(osascript - "$MOTION_CHECK_PID" <<'APPLESCRIPT'
on run argv
    tell application "System Events"
        repeat 50 times
            if exists (first application process whose unix id is (item 1 of argv as integer)) then exit repeat
            delay 0.1
        end repeat
        set testProcess to first application process whose unix id is (item 1 of argv as integer)
        repeat 20 times
            if (count of menu bars of testProcess) > 1 then exit repeat
            delay 0.1
        end repeat
        set testItem to first menu bar item of menu bar 2 of testProcess
        set p to position of testItem
        set s to size of testItem
        return ((item 1 of p) + (item 1 of s) / 2) as text & " " & ((item 2 of p) + (item 2 of s) / 2) as text
    end tell
end run
APPLESCRIPT
)
read -r MOTION_X MOTION_Y <<< "$MOTION_POINT"
"$WORK/click-probe" "$MOTION_X" "$MOTION_Y"
# Bound the run if the menu could not open (e.g. another app takes focus).
(sleep 12; kill "$MOTION_CHECK_PID" 2>/dev/null || true) &
MOTION_WATCHDOG_PID=$!
wait "$MOTION_CHECK_PID"
kill "$MOTION_WATCHDOG_PID" 2>/dev/null || true
