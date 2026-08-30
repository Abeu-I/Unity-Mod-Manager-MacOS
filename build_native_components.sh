#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/third_party/UnityDoorstop.Unix"
BUILD_DIR="$SCRIPT_DIR/build"

command -v clang >/dev/null 2>&1 || {
    echo "Apple command-line tools are required. Run: xcode-select --install" >&2
    exit 1
}
command -v lipo >/dev/null 2>&1 || {
    echo "lipo was not found in the Apple command-line tools." >&2
    exit 1
}

mkdir -p "$BUILD_DIR"

COMMON_FLAGS=(-O2 -Wall -Wextra -shared -fPIC -D OSX -D AMD64)
clang "${COMMON_FLAGS[@]}" -arch x86_64 -mmacosx-version-min=12.0 \
    -o "$BUILD_DIR/libdoorstop_x86_64.dylib" \
    "$SOURCE_DIR/doorstop.c" "$SOURCE_DIR/plthook_osx.c"
clang "${COMMON_FLAGS[@]}" -arch arm64 -mmacosx-version-min=12.0 \
    -o "$BUILD_DIR/libdoorstop_arm64.dylib" \
    "$SOURCE_DIR/doorstop.c" "$SOURCE_DIR/plthook_osx.c"
lipo -create \
    "$BUILD_DIR/libdoorstop_x86_64.dylib" \
    "$BUILD_DIR/libdoorstop_arm64.dylib" \
    -output "$SCRIPT_DIR/libdoorstop_adofai_macos.dylib"
codesign --force --sign - "$SCRIPT_DIR/libdoorstop_adofai_macos.dylib" >/dev/null

clang -O2 -Wall -Wextra -arch x86_64 -mmacosx-version-min=12.0 \
    -o "$SCRIPT_DIR/adofai_steam_bundle_launcher" \
    "$SCRIPT_DIR/src/adofai_steam_bundle_launcher.c"
codesign --force --sign - "$SCRIPT_DIR/adofai_steam_bundle_launcher" >/dev/null

echo "Built native components successfully."
