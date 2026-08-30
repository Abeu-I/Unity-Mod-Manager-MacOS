#!/bin/bash
set -euo pipefail

ACTION="${1:-enable}"
APP_ID="977950"
STEAM_ROOT="$HOME/Library/Application Support/Steam"
GAME_APP=""

case "$ACTION" in
    enable|disable) shift || true ;;
    -h|--help)
        echo "Usage: $(basename "$0") [enable|disable] [--game-app PATH]"
        exit 0
        ;;
    *) echo "Usage: $(basename "$0") [enable|disable] [--game-app PATH]" >&2; exit 64 ;;
esac

while [ "$#" -gt 0 ]; do
    case "$1" in
        --game-app)
            [ "$#" -ge 2 ] || { echo "--game-app requires a path" >&2; exit 64; }
            GAME_APP="$2"
            shift 2
            ;;
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

find_game_app() {
    if [ -n "$GAME_APP" ]; then
        [ -d "$GAME_APP" ] || { echo "Game app not found: $GAME_APP" >&2; exit 1; }
        return
    fi

    for candidate in \
        "$STEAM_ROOT/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app" \
        "$STEAM_ROOT/steamapps/common/A Dance of Fire and Ice/ADOFAI.app"; do
        if [ -d "$candidate" ]; then
            GAME_APP="$candidate"
            return
        fi
    done

    library_file="$STEAM_ROOT/config/libraryfolders.vdf"
    if [ -f "$library_file" ]; then
        while IFS= read -r library_path; do
            for app_name in ADanceOfFireAndIce.app ADOFAI.app; do
                candidate="$library_path/steamapps/common/A Dance of Fire and Ice/$app_name"
                if [ -d "$candidate" ]; then
                    GAME_APP="$candidate"
                    return
                fi
            done
        done <<EOF
$(awk -F'"' '$2 == "path" { print $4 }' "$library_file")
EOF
    fi

    echo "ADOFAI was not found in the Steam libraries." >&2
    exit 1
}

if pgrep -x steam_osx >/dev/null 2>&1 || pgrep -x Steam >/dev/null 2>&1; then
    echo "Quit Steam completely before changing its launch option." >&2
    exit 1
fi

if [ "$ACTION" = "enable" ]; then
    find_game_app
    GAME_ROOT="$(dirname "$GAME_APP")"
    BUNDLE_MARKER="$GAME_ROOT/.adofai-umm-macos/steam-bundle-launcher-installed.txt"
    [ -f "$BUNDLE_MARKER" ] || {
        echo "Steam-compatible bundle launcher is not installed. Run the mod installer first." >&2
        exit 1
    }
fi
LAUNCH_OPTION=""
CONFIG_ACTION="disable"

/usr/bin/python3 - "$STEAM_ROOT" "$CONFIG_ACTION" "$APP_ID" "$LAUNCH_OPTION" <<'PY'
import datetime
import glob
import os
import re
import shutil
import sys
import tempfile

steam_root, action, app_id, launch_option = sys.argv[1:]
configs = sorted(glob.glob(os.path.join(
    steam_root, "userdata", "*", "config", "localconfig.vdf")))
if not configs:
    raise SystemExit("No Steam user configuration was found.")

target = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", app_id]
key_only = re.compile(r'^"((?:\\.|[^"\\])*)"\s*$')
launch_pattern = re.compile(r'^\s*"LaunchOptions"\s+"(?:\\.|[^"\\])*"\s*$')
matched = 0

for config_path in configs:
    with open(config_path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()

    stack = []
    pending_key = None
    block_start = None
    block_end = None

    for index, line in enumerate(lines):
        stripped = line.strip()
        match = key_only.match(stripped)
        if match:
            pending_key = match.group(1)
            continue
        if stripped == "{":
            stack.append(pending_key)
            pending_key = None
            if stack == target:
                block_start = index
            continue
        if stripped == "}":
            if stack == target:
                block_end = index
                break
            if stack:
                stack.pop()
            pending_key = None
            continue
        pending_key = None

    if block_start is None or block_end is None:
        continue

    matched += 1
    launch_line = None
    for index in range(block_start + 1, block_end):
        if launch_pattern.match(lines[index].rstrip("\r\n")):
            launch_line = index
            break

    if action == "disable":
        if launch_line is None:
            print(f"Steam profile already uses the normal Play action: {config_path}")
            continue
        del lines[launch_line]
    else:
        escaped = launch_option.replace("\\", "\\\\").replace('"', '\\"')
        closing_indent = re.match(r"^\s*", lines[block_end]).group(0)
        replacement = f'{closing_indent}\t"LaunchOptions"\t\t"{escaped}"\n'
        if launch_line is None:
            lines.insert(block_end, replacement)
        else:
            lines[launch_line] = replacement

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"{config_path}.adofai-umm-backup.{stamp}"
    suffix = 0
    while os.path.exists(backup):
        suffix += 1
        backup = f"{config_path}.adofai-umm-backup.{stamp}-{suffix}"
    shutil.copy2(config_path, backup)

    directory = os.path.dirname(config_path)
    with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=directory, delete=False) as handle:
        temp_path = handle.name
        handle.writelines(lines)
    shutil.copymode(config_path, temp_path)
    os.replace(temp_path, config_path)
    print(f"Steam config backup: {backup}")

if matched == 0:
    raise SystemExit(f"No Steam profile with ADOFAI app {app_id} was found. Launch the game once normally, quit Steam, and retry.")
PY

if [ "$ACTION" = "enable" ]; then
    echo "Steam Play now uses ADOFAI's Steam-compatible in-bundle mod launcher."
else
    echo "Steam Play launch override removed."
fi
