#!/bin/bash
# Stage and verify a build, keep a durable backup, then replace with rollback on failure.
# tools/install-app.sh BUILT.app [/absolute/path/SoundPin.app] [BACKUP_ROOT] [--no-launch]
set -euo pipefail

BUILT="${1:?Pass the built SoundPin.app}"
DEST="${2:-/Applications/SoundPin.app}"
BACKUP_ROOT="${3:-$HOME/Library/Application Support/SoundPin/Backups}"
LAUNCH=true
if [[ "${4:-}" == "--no-launch" ]]; then LAUNCH=false; fi

[[ -d "$BUILT" && -x "$BUILT/Contents/MacOS/SoundPin" ]] || { echo "Missing built application: $BUILT" >&2; exit 1; }
[[ "$DEST" == /* && ! -L "$DEST" ]] || { echo "Destination must be an absolute path, not a symlink: $DEST" >&2; exit 1; }
[[ ! -e "$DEST" || -d "$DEST" ]] || { echo "Destination is not an application directory: $DEST" >&2; exit 1; }
[[ "${DEST##*/}" == SoundPin.app ]] || { echo "Destination must be named SoundPin.app: $DEST" >&2; exit 1; }
for application in "$BUILT" "$DEST"; do
    if [[ -e "$application" ]]; then
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$application/Contents/Info.plist" 2>/dev/null || true)
        [[ "$identifier" == io.github.realruian.SoundPin ]] || { echo "Refusing to replace an unexpected application: $application" >&2; exit 1; }
    fi
done
PARENT=$(dirname "$DEST")
[[ -d "$PARENT" ]] || { echo "Destination folder does not exist: $PARENT" >&2; exit 1; }
STAGE=$(mktemp -d "$PARENT/.SoundPin-install.XXXXXX")
BACKUP=""
INSTALLED=false
SUCCEEDED=false
WAS_RUNNING=false

cleanup() {
    result=$?
    trap - EXIT
    if ! $SUCCEEDED; then
        # The old application remains on the same volume until all installation steps pass.
        if $INSTALLED && [[ -e "$DEST" ]]; then
            if ! mv "$DEST" "$STAGE/Failed.app"; then
                echo "Could not move failed installation. Recovery files: $STAGE; backup: $BACKUP" >&2
                exit 1
            fi
        fi
        if [[ -d "$STAGE/Previous.app" ]]; then
            if ! mv "$STAGE/Previous.app" "$DEST"; then
                echo "Could not restore application. Recovery files: $STAGE; backup: $BACKUP" >&2
                exit 1
            fi
            echo "Restored previous application: $DEST" >&2
        fi
        if $WAS_RUNNING && $LAUNCH && [[ -d "$DEST" ]]; then open "$DEST" || true; fi
    fi
    rm -rf "$STAGE"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$BUILT" "$STAGE/New.app"
codesign --verify --deep --strict "$STAGE/New.app"
if [[ -d "$DEST" ]]; then
    mkdir -p "$BACKUP_ROOT"
    BACKUP=$(mktemp -d "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")
    ditto "$DEST" "$BACKUP/SoundPin.app"
    echo "Previous application backed up to: $BACKUP/SoundPin.app"
fi

# Do not stop another checkout or copy of SoundPin. The old target is stopped only after staging and backup.
for pid in $(pgrep -x SoundPin || true); do
    executable=$(ps -p "$pid" -o comm= || true)
    if [[ "$executable" == "$DEST/Contents/MacOS/SoundPin" ]]; then
        WAS_RUNNING=true
        kill -TERM "$pid"
        for _ in {1..50}; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "SoundPin has not exited; leaving the installed application intact." >&2
            exit 1
        fi
    fi
done

if [[ -d "$DEST" ]]; then mv "$DEST" "$STAGE/Previous.app"; fi
# Mark the destination as ours before moving: a signal after rename must still roll it back.
INSTALLED=true
mv "$STAGE/New.app" "$DEST"
codesign --verify --deep --strict "$DEST"
if $LAUNCH; then open "$DEST"; fi
SUCCEEDED=true
echo "Installed: $DEST"
