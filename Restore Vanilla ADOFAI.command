#!/bin/bash
# Reversibly disables the macOS UMM loader and restores Steam's normal launch.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

pause_before_close() {
    if [ -t 0 ] && [ "${ADOFAI_INSTALLER_NO_PAUSE:-0}" != "1" ]; then
        printf '\nPress Return to close this window.'
        IFS= read -r _ || true
    fi
}

finish() {
    status=$?
    if [ "$status" -ne 0 ]; then
        printf '\nRestore stopped with an error. No game files were deleted.\n' >&2
    fi
    pause_before_close
    exit "$status"
}
trap finish EXIT INT TERM

printf '%s\n' \
    'Restore normal ADOFAI launch' \
    '----------------------------' \
    'This removes any Steam launch override, restores the original game' \
    'executable, and moves the UMM loader into a dated backup.' \
    'Downloaded mods are preserved but will not load.'

if pgrep -f 'ADanceOfFireAndIce.app/Contents/MacOS' >/dev/null 2>&1 || \
   pgrep -f 'ADOFAI.app/Contents/MacOS' >/dev/null 2>&1; then
    echo "Close ADOFAI, then run this file again." >&2
    exit 1
fi

if pgrep -x steam_osx >/dev/null 2>&1 || pgrep -x Steam >/dev/null 2>&1; then
    printf '\nQuit Steam now? [Y/n] '
    IFS= read -r answer
    case "$answer" in
        n|N|no|NO|No) echo "Quit Steam, then run this file again." >&2; exit 1 ;;
    esac
    osascript -e 'tell application "Steam" to quit' >/dev/null 2>&1 || true
    attempts=0
    while pgrep -x steam_osx >/dev/null 2>&1 || pgrep -x Steam >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [ "$attempts" -le 20 ] || { echo "Steam did not quit." >&2; exit 1; }
        sleep 1
    done
fi

"$SCRIPT_DIR/configure_adofai_steam_launch.sh" disable
"$SCRIPT_DIR/setup_adofai_umm_macos.sh" uninstall

printf '\nNormal Steam launch restored. Your mod folders were preserved.\n'
open -a Steam >/dev/null 2>&1 || true
