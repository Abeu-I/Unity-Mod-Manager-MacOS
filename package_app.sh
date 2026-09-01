#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_NAME="ADOFAI Mod Installer"
BUILD_ROOT="$SCRIPT_DIR/build/app"
APP="$SCRIPT_DIR/dist/$APP_NAME.app"

"$SCRIPT_DIR/build_native_components.sh"
swift build --package-path "$SCRIPT_DIR/app" -c release --scratch-path "$BUILD_ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Tools/src" "$APP/Contents/Resources/Tools/third_party" "$APP/Contents/Resources/Tools/mods"
cp "$BUILD_ROOT/release/ADOFAIModInstaller" "$APP/Contents/MacOS/ADOFAIModInstaller"

for item in setup_adofai_umm_macos.sh configure_adofai_steam_launch.sh build_native_components.sh build_mac_autoplay.sh; do
    cp "$SCRIPT_DIR/$item" "$APP/Contents/Resources/Tools/$item"
done
cp "$SCRIPT_DIR/libdoorstop_adofai_macos.dylib" "$APP/Contents/Resources/Tools/libdoorstop_adofai_macos.dylib"
cp "$SCRIPT_DIR/adofai_steam_bundle_launcher" "$APP/Contents/Resources/Tools/adofai_steam_bundle_launcher"
cp -R "$SCRIPT_DIR/src/." "$APP/Contents/Resources/Tools/src/"
cp -R "$SCRIPT_DIR/third_party/." "$APP/Contents/Resources/Tools/third_party/"
cp -R "$SCRIPT_DIR/mods/." "$APP/Contents/Resources/Tools/mods/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>ADOFAIModInstaller</string>
  <key>CFBundleIdentifier</key><string>com.abexlz.adofai-mod-installer</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>ADOFAI Mod Installer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

chmod +x "$APP/Contents/MacOS/ADOFAIModInstaller" "$APP/Contents/Resources/Tools"/*.sh
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP" >/dev/null
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built: $APP"
