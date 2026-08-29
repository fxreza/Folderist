#!/usr/bin/env bash
# Build Folderist in release mode and assemble a launchable .app bundle at build/Folderist.app.
# Idempotent: safe to re-run; always produces a clean bundle from the latest build.
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

echo "==> Building $APP_NAME (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
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

if [[ -d "$ROOT_DIR/Folderist/Resources/BaseFolder" ]]; then
    echo "==> Copying base folder artwork..."
    rsync -a --delete "$ROOT_DIR/Folderist/Resources/BaseFolder/" "$RESOURCES_DIR/BaseFolder/"
fi

echo "==> Ad-hoc codesigning..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Done."
echo "$APP_BUNDLE"
