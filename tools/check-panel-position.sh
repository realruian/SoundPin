#!/bin/bash
# Geometry-only regression checks; does not open windows or touch audio/settings.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=".build/panel-position-check"
mkdir -p "$WORK"
swiftc -module-cache-path "$WORK/ModuleCache" -parse-as-library -o "$WORK/check" \
  SoundPin/Models/PanelPlacement.swift tools/PanelPlacementCheckMain.swift
"$WORK/check"
