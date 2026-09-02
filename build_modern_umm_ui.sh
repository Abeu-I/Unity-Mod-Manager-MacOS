#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GAME_APP="${ADOFAI_GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app}"
INSTALL=0

if [ "${1:-}" = "--install" ]; then
    INSTALL=1
elif [ "$#" -gt 0 ]; then
    echo "Usage: $(basename "$0") [--install]" >&2
    exit 64
fi

command -v mcs >/dev/null 2>&1 || {
    echo "Mono's C# compiler is required. Install it with: brew install mono" >&2
    exit 1
}

MANAGED="$GAME_APP/Contents/Resources/Data/Managed"
SOURCE="$SCRIPT_DIR/mods/ModernUMMUI"
OUTPUT="$SCRIPT_DIR/build/ModernUMMUI"

for required in \
    "$MANAGED/UnityEngine.dll" \
    "$MANAGED/UnityEngine.CoreModule.dll" \
    "$MANAGED/UnityEngine.IMGUIModule.dll" \
    "$MANAGED/UnityEngine.TextRenderingModule.dll" \
    "$MANAGED/netstandard.dll" \
    "$MANAGED/UnityModManager/UnityModManager.dll" \
    "$MANAGED/UnityModManager/0Harmony.dll"; do
    [ -f "$required" ] || { echo "Required assembly missing: $required" >&2; exit 1; }
done

mkdir -p "$OUTPUT"
mcs -target:library -optimize+ \
    -out:"$OUTPUT/ModernUMMUI.dll" \
    -r:"$MANAGED/UnityEngine.dll" \
    -r:"$MANAGED/UnityEngine.CoreModule.dll" \
    -r:"$MANAGED/UnityEngine.IMGUIModule.dll" \
    -r:"$MANAGED/UnityEngine.TextRenderingModule.dll" \
    -r:"$MANAGED/netstandard.dll" \
    -r:"$MANAGED/UnityModManager/UnityModManager.dll" \
    -r:"$MANAGED/UnityModManager/0Harmony.dll" \
    "$SOURCE/Main.cs"
cp "$SOURCE/Info.json" "$OUTPUT/Info.json"

echo "Built: $OUTPUT"
if [ "$INSTALL" -eq 1 ]; then
    "$SCRIPT_DIR/setup_adofai_umm_macos.sh" add-mod --mod "$OUTPUT"
fi
