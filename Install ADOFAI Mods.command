#!/bin/bash
# Double-click installer for the native ADOFAI macOS UMM setup.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DRY_RUN=0
TEMP_DIR=""

ADOFAI_TWEAKS_URL="https://github.com/PizzaLovers007/AdofaiTweaks/releases/download/v2.9.2/AdofaiTweaks-2.9.2.zip"
ADOFAI_TWEAKS_SHA256="54f95784ed5833b7df091ce2fd2d544aa26d5014752041240c1e5dc4e5103c2d"
JALIB_URL="https://github.com/Jongye0l/JALib/releases/download/v1.0.0.45/JALib.zip"
JALIB_SHA256="93938ff8020bb6b2aa3d9ff95f22de71b2d91ea2c14548c205450d8ea9b0fc61"
JIPPER_URL="https://github.com/Jongye0l/JipperResourcePack/releases/download/v1.4.9.0/JipperResourcePack.zip"
JIPPER_SHA256="15bf36cb31180bd4d2ca6b6cff5db03776084b09d208bf7761502c6fb6bfdd46"

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
elif [ "$#" -gt 0 ]; then
    echo "Usage: $(basename "$0") [--dry-run]" >&2
    exit 64
fi

pause_before_close() {
    if [ -t 0 ] && [ "${ADOFAI_INSTALLER_NO_PAUSE:-0}" != "1" ]; then
        printf '\nPress Return to close this window.'
        IFS= read -r _ || true
    fi
}

cleanup() {
    status=$?
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        case "$TEMP_DIR" in
            /private/tmp/adofai-friend-installer.*) rm -rf "$TEMP_DIR" ;;
        esac
    fi
    if [ "$status" -ne 0 ]; then
        printf '\nInstallation stopped with an error. Nothing from Steam or ADOFAI was deleted.\n' >&2
    fi
    pause_before_close
    exit "$status"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

download_mod() {
    mod_name="$1"
    expected_id="$2"
    url="$3"
    expected_hash="$4"
    archive="$TEMP_DIR/$expected_id.zip"
    extract_dir="$TEMP_DIR/$expected_id"

    printf '\nDownloading %s from its official release...\n' "$mod_name" >&2
    curl -fL --retry 2 --connect-timeout 20 "$url" -o "$archive"
    actual_hash="$(sha256_file "$archive")"
    [ "$actual_hash" = "$expected_hash" ] || fail "$mod_name download did not match its published SHA-256 checksum."

    mkdir -p "$extract_dir"
    unzip -q "$archive" -d "$extract_dir"
    info_file="$(find "$extract_dir" -maxdepth 4 -type f -name Info.json | head -n 1 || true)"
    [ -n "$info_file" ] || fail "$mod_name package does not contain Info.json."
    mod_id="$(sed -nE 's/^[[:space:]]*"Id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$info_file" | head -n 1)"
    [ "$mod_id" = "$expected_id" ] || fail "$mod_name package has unexpected mod ID '$mod_id'."
    dirname "$info_file"
}

for required in \
    "$SCRIPT_DIR/setup_adofai_umm_macos.sh" \
    "$SCRIPT_DIR/configure_adofai_steam_launch.sh" \
    "$SCRIPT_DIR/libdoorstop_adofai_macos.dylib" \
    "$SCRIPT_DIR/adofai_umm_launcher" \
    "$SCRIPT_DIR/adofai_steam_bundle_launcher"; do
    [ -f "$required" ] || fail "Installer component is missing: $(basename "$required")"
done

[ "$(uname -s)" = "Darwin" ] || fail "This installer is only for macOS."
command -v curl >/dev/null 2>&1 || fail "macOS curl is missing."
command -v unzip >/dev/null 2>&1 || fail "macOS unzip is missing."

clear 2>/dev/null || true
printf '%s\n' \
    'ADOFAI macOS Mod Installer' \
    '---------------------------' \
    'Installs native UMM support plus:' \
    '  - AdofaiTweaks 2.9.2' \
    '  - JALib 1.0.0.45 beta45' \
    '  - Jipper Resource Pack 1.4.9.0' \
    '' \
    'No Wine/Whisky is used. SIP is not changed.' \
    'Steam Workshop, playtime, overlay, and achievements stay connected.' \
    '' \
    'The game must already be installed through Steam.'

if [ "$DRY_RUN" -eq 0 ]; then
    if pgrep -f 'ADanceOfFireAndIce.app/Contents/MacOS' >/dev/null 2>&1 || \
       pgrep -f 'ADOFAI.app/Contents/MacOS' >/dev/null 2>&1; then
        fail "ADOFAI is running. Close the game and run this installer again."
    fi

    if pgrep -x steam_osx >/dev/null 2>&1 || pgrep -x Steam >/dev/null 2>&1; then
        printf '\nSteam must close briefly so its ADOFAI Play setting can be updated.\n'
        printf 'Quit Steam now? [Y/n] '
        IFS= read -r answer
        case "$answer" in
            n|N|no|NO|No) fail "Quit Steam, then run the installer again." ;;
        esac
        osascript -e 'tell application "Steam" to quit' >/dev/null 2>&1 || true
        attempts=0
        while pgrep -x steam_osx >/dev/null 2>&1 || pgrep -x Steam >/dev/null 2>&1; do
            attempts=$((attempts + 1))
            [ "$attempts" -le 20 ] || fail "Steam did not quit. Quit it manually, then run the installer again."
            sleep 1
        done
    fi
fi

if ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
        fail "Rosetta 2 is required but is not installed."
    fi
    printf '\nApple Rosetta 2 is required for these mods on Apple Silicon.\n'
    printf 'Install Rosetta now using Apple softwareupdate? [Y/n] '
    IFS= read -r answer
    case "$answer" in
        n|N|no|NO|No) fail "Rosetta installation was declined." ;;
    esac
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi

TEMP_DIR="$(mktemp -d /private/tmp/adofai-friend-installer.XXXXXX)"

ADOFAI_TWEAKS_DIR="$(download_mod 'AdofaiTweaks' 'AdofaiTweaks' "$ADOFAI_TWEAKS_URL" "$ADOFAI_TWEAKS_SHA256")"
JALIB_DIR="$(download_mod 'JALib' 'JALib' "$JALIB_URL" "$JALIB_SHA256")"
JIPPER_DIR="$(download_mod 'Jipper Resource Pack' 'JipperResourcePack' "$JIPPER_URL" "$JIPPER_SHA256")"

if [ "$DRY_RUN" -eq 1 ]; then
    "$SCRIPT_DIR/setup_adofai_umm_macos.sh" install --dry-run
    printf '\nDry run passed. All packages, checksums, and Mac requirements are valid.\n'
    exit 0
fi

printf '\nInstalling the native mod loader...\n'
"$SCRIPT_DIR/setup_adofai_umm_macos.sh" install
"$SCRIPT_DIR/setup_adofai_umm_macos.sh" add-mod --mod "$ADOFAI_TWEAKS_DIR"
"$SCRIPT_DIR/setup_adofai_umm_macos.sh" add-mod --mod "$JALIB_DIR"
"$SCRIPT_DIR/setup_adofai_umm_macos.sh" add-mod --mod "$JIPPER_DIR"
"$SCRIPT_DIR/configure_adofai_steam_launch.sh" disable

printf '\n%s\n' \
    'Installation complete.' \
    'Open Steam and press Play on A Dance of Fire and Ice.' \
    'To open UMM in game, press Control+F10 (or Control+Fn+F10).' \
    '' \
    'Note: Jipper Resource Pack loads on macOS, but its own Key Viewer is' \
    'Windows-only. Other Jipper resource and overlay features remain available.'

open -a Steam >/dev/null 2>&1 || true
