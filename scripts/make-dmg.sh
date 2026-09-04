#!/usr/bin/env bash
# Package build/Folderist.app as a distributable build/Folderist.dmg.
#
# Builds the app first if it is missing, then lays out a staging folder with
# the app plus an /Applications symlink so the DMG opens as the usual
# drag-to-install window. Idempotent: safe to re-run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Folderist"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
STAGE_DIR="$BUILD_DIR/dmg-stage"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "==> $APP_BUNDLE not found, building it first..."
    "$ROOT_DIR/scripts/build.sh"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
VOL_NAME="$APP_NAME $VERSION"

echo "==> Staging $VOL_NAME..."
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
ditto "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating $DMG_PATH..."
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

echo "==> Verifying..."
hdiutil verify "$DMG_PATH" >/dev/null

echo "==> Done. $(du -h "$DMG_PATH" | cut -f1)"
echo "$DMG_PATH"
