#!/usr/bin/env bash
# Generates Folderist's own app icon using its own renderer: an indigo->cyan
# gradient folder with an embossed SF Symbol, via FolderIconRenderer +
# ExportService (the exact code path the app itself uses to build .icns
# exports), so there's no separate hand-drawn icon to keep in sync.
#
# Usage:
#   scripts/make-appicon.sh [symbol-name]
#
# Defaults to "paintpalette.fill" (tried against "paintbrush.pointed.fill";
# the palette's rounded, symmetric silhouette held up better at small sizes
# like the 16px Finder list icon). Writes:
#   - Folderist/Resources/AppIcon.icns   (committed to the repo tree)
#   - a 512px preview PNG (path printed at the end)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYMBOL="${1:-paintpalette.fill}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TOOL="$WORK_DIR/generate-appicon"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
ICNS_OUT="$ROOT_DIR/Folderist/Resources/AppIcon.icns"
PREVIEW_OUT="${APPICON_PREVIEW_OUT:-$WORK_DIR/appicon-preview.png}"

echo "==> Compiling icon generator (symbol: $SYMBOL)..."
swiftc -O \
    "$ROOT_DIR/Folderist/Rendering/RenderSupport.swift" \
    "$ROOT_DIR/Folderist/Rendering/FolderGeometry.swift" \
    "$ROOT_DIR/Folderist/Rendering/OverlayCompositor.swift" \
    "$ROOT_DIR/Folderist/Rendering/RenderResources.swift" \
    "$ROOT_DIR/Folderist/Rendering/FolderIconRenderer.swift" \
    "$ROOT_DIR/Folderist/Models/CoreModels.swift" \
    "$ROOT_DIR/Folderist/Services/ExportService.swift" \
    "$ROOT_DIR/scripts/appicon/main.swift" \
    -o "$TOOL"

echo "==> Rendering icon set..."
"$TOOL" "$SYMBOL" "$ROOT_DIR/Assets" "$PREVIEW_OUT" "$ICONSET_DIR" "$ICNS_OUT"

echo "==> Done."
echo "AppIcon.icns: $ICNS_OUT"
echo "Preview PNG:  $PREVIEW_OUT"
