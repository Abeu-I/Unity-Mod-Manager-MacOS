#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
FIXED_DOORSTOP_URL="https://github.com/abexlz/Unity-Mod-Manager-MacOS/releases/download/v1.1/libdoorstop_adofai_macos.dylib"
FIXED_DOORSTOP_SHA256="06a0bddc0e5ae259beb98b9922e09b635677b12012b7ae407711be29a00ab612"

command -v clang >/dev/null 2>&1 || {
    echo "Apple command-line tools are required. Run: xcode-select --install" >&2
    exit 1
}
command -v lipo >/dev/null 2>&1 || {
    echo "lipo was not found in the Apple command-line tools." >&2
    exit 1
}

mkdir -p "$BUILD_DIR/doorstop"
doorstop="$SCRIPT_DIR/libdoorstop_adofai_macos.dylib"
if [ -n "${ADOFAI_DOORSTOP_DYLIB:-}" ]; then
    cp "$ADOFAI_DOORSTOP_DYLIB" "$doorstop"
elif [ -f "$doorstop" ] && [ "$(shasum -a 256 "$doorstop" | awk '{print $1}')" = "$FIXED_DOORSTOP_SHA256" ]; then
    :
else
    curl -fL --retry 5 --connect-timeout 20 "$FIXED_DOORSTOP_URL" -o "$doorstop"
fi
actual_hash="$(shasum -a 256 "$doorstop" | awk '{print $1}')"
[ "$actual_hash" = "$FIXED_DOORSTOP_SHA256" ] || {
    echo "Verified ADOFAI Doorstop checksum mismatch: $actual_hash" >&2
    exit 1
}
codesign --verify "$doorstop" >/dev/null 2>&1 || {
    echo "Verified ADOFAI Doorstop signature is invalid." >&2
    exit 1
}

clang -O2 -Wall -Wextra -arch x86_64 -mmacosx-version-min=12.0 \
    -o "$SCRIPT_DIR/adofai_steam_bundle_launcher" \
    "$SCRIPT_DIR/src/adofai_steam_bundle_launcher.c"
codesign --force --sign - "$SCRIPT_DIR/adofai_steam_bundle_launcher" >/dev/null

echo "Built native components successfully."
