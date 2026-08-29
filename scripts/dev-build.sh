#!/usr/bin/env bash
# Same as build.sh but uses a debug build for fast iteration.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Folderist"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ASSET_PACKS_DIR="$RESOURCES_DIR/AssetPacks"

echo "==> Building $APP_NAME (debug)..."
swift build

BIN_PATH="$(swift build --show-bin-path)"
BUILT_BINARY="$BIN_PATH/$APP_NAME"

if [[ ! -f "$BUILT_BINARY" ]]; then
    echo "error: built binary not found at $BUILT_BINARY" >&2
    exit 1
fi

echo "==> Assembling app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ASSET_PACKS_DIR"

cp "$BUILT_BINARY" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Folderist/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "==> Copying asset packs..."
rsync -a --delete "$ROOT_DIR/Assets/emoji/" "$ASSET_PACKS_DIR/emoji/"
rsync -a --delete "$ROOT_DIR/Assets/icons/" "$ASSET_PACKS_DIR/icons/"
rsync -a --delete "$ROOT_DIR/Assets/symbols/" "$ASSET_PACKS_DIR/symbols/"
rsync -a --delete "$ROOT_DIR/Assets/textures/" "$ASSET_PACKS_DIR/textures/"
rsync -a --delete "$ROOT_DIR/Assets/licenses/" "$ASSET_PACKS_DIR/licenses/"

if [[ -f "$ROOT_DIR/Folderist/Resources/AppIcon.icns" ]]; then
    echo "==> Copying app icon..."
    cp "$ROOT_DIR/Folderist/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "==> Ad-hoc codesigning..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Done."
echo "$APP_BUNDLE"
