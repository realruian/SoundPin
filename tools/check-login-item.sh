#!/bin/bash
# Login item approval and error feedback using an injected service, never SMAppService writes.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=".build/login-item-check"
mkdir -p "$WORK"
swiftc -warnings-as-errors -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$WORK/ModuleCache" SoundPin/Models/*.swift \
  SoundPin/Services/LaunchAtLoginManager.swift tools/LoginItemCheckMain.swift -o "$WORK/check"
"$WORK/check"
