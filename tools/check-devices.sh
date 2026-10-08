#!/bin/bash
# Prints which list and which icon a table of sample devices gets, to check the
# rules after changing them. Reads only; it does not touch the audio devices.
#   tools/check-devices.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/scenario"
mkdir -p "$WORK/src"
cp AudioPriorityBar/Models/*.swift AudioPriorityBar/Services/*.swift AudioPriorityBar/Views/*.swift "$WORK/src/"
sed 's/^@main$//' AudioPriorityBar/AudioPriorityBarApp.swift > "$WORK/src/AudioPriorityBarApp.swift"
cp tools/ScenarioMain.swift "$WORK/src/"
swiftc -suppress-warnings -parse-as-library -o "$WORK/apbscenario" "$WORK"/src/*.swift

"$WORK/apbscenario" "$@"
