#!/bin/bash
# Exercise real filesystem staging/backup/rollback in a temporary directory.
# Only signing, app discovery and launching are stubbed; never touches /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/soundpin-install-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
cat > "$WORK/bin/codesign" <<'SH'
#!/bin/bash
if [[ "$SOUNDPIN_INSTALL_TEST_CASE" == verify-failure && "${@: -1}" == */Installed/SoundPin.app ]]; then exit 24; fi
exit 0
SH
cat > "$WORK/bin/ditto" <<'SH'
#!/bin/bash
if [[ "$SOUNDPIN_INSTALL_TEST_CASE" == copy-failure && "$2" == */New.app ]]; then exit 23; fi
if [[ "$SOUNDPIN_INSTALL_TEST_CASE" == backup-failure && "$2" == */Backups/* ]]; then exit 25; fi
exec /usr/bin/ditto "$@"
SH
cat > "$WORK/bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
cat > "$WORK/bin/open" <<'SH'
#!/bin/bash
if [[ "$SOUNDPIN_INSTALL_TEST_CASE" == launch-failure ]]; then exit 26; fi
exit 0
SH
cat > "$WORK/bin/mv" <<'SH'
#!/bin/bash
/bin/mv "$@" || exit $?
if [[ "$SOUNDPIN_INSTALL_TEST_CASE" == post-move-failure && "$1" == */New.app ]]; then exit 27; fi
SH
chmod +x "$WORK/bin/"*

for scenario in success copy-failure backup-failure verify-failure launch-failure post-move-failure target-mismatch; do
    case_dir="$WORK/$scenario"
    built="$case_dir/Built.app"
    destination="$case_dir/Installed/SoundPin.app"
    for app in "$built" "$destination"; do
        mkdir -p "$app/Contents/MacOS"
        printf '#!/bin/sh\nexit 0\n' > "$app/Contents/MacOS/SoundPin"
        chmod +x "$app/Contents/MacOS/SoundPin"
        cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>io.github.realruian.SoundPin</string></dict></plist>
PLIST
    done
    echo new > "$built/version.txt"
    echo old > "$destination/version.txt"
    if [[ "$scenario" == target-mismatch ]]; then
        /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.OtherApp' "$destination/Contents/Info.plist"
    fi
    status=0
    PATH="$WORK/bin:$PATH" SOUNDPIN_INSTALL_TEST_CASE="$scenario" \
        bash "$ROOT/tools/install-app.sh" "$built" "$destination" "$case_dir/Backups" > "$case_dir/log" 2>&1 || status=$?
    if [[ "$scenario" == success ]]; then
        [[ $status == 0 && $(cat "$destination/version.txt") == new ]]
    else
        [[ $status != 0 && $(cat "$destination/version.txt") == old ]]
    fi
    if [[ "$scenario" == success || "$scenario" == verify-failure || "$scenario" == launch-failure || "$scenario" == post-move-failure ]]; then
        saved=("$case_dir/Backups/"*/SoundPin.app/version.txt)
        [[ ${#saved[@]} == 1 && $(cat "${saved[0]}") == old ]]
    fi
    echo "ok: $scenario preserves the expected application and backup"
done
echo "7 installation scenarios passed. No installed application or running process was changed."
