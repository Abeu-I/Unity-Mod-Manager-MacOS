#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_NAME="ADOFAI Mod Installer"
DMG="$SCRIPT_DIR/dist/ADOFAI-Mod-Installer.dmg"
STAGING="$SCRIPT_DIR/build/dmg"

"$SCRIPT_DIR/package_app.sh"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$SCRIPT_DIR/dist/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -format UDZO "$DMG"

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built: $DMG"
