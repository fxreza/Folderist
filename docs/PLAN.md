# Folderist — Technical Plan

## Stack

- Swift 5.10+, SwiftUI (AppKit interop where needed: NSColorSampler, drag-and-drop of file promises, status item window).
- Xcode project generated with **XcodeGen** (`project.yml`) so the project file stays diff-friendly; buildable via `xcodebuild`.
- macOS 14+ deployment target. App Sandbox ON with user-selected read/write; icon application via `NSWorkspace.shared.setIcon(_:forFile:)` works on dropped/selected folders because drag-and-drop grants sandbox access.

## Architecture

```
Folderist/
  App/            FolderistApp.swift, AppDelegate (status item), MainWindow
  Models/         Style, Asset, OverlayKind, EffectSettings, Library (Codable documents)
  Rendering/      FolderIconRenderer — composites base folder + color/gradient tint
                  + overlay (symbol/emoji/text/image modes) + effects into NSImage
                  at 16/32/64/128/256/512/1024. Core of the app; pure + testable.
  Services/       IconApplier (NSWorkspace setIcon, batch, aliases),
                  SmartRestoreStore (snapshots original icons),
                  TagService (Finder color tags), ExportService (.icns/.iconset/png),
                  AssetStore (persistence, autosave, iCloud Drive optional),
                  AssetImporter (bundled SVG/emoji catalogs, search index)
  Views/          StyleGridView, StyleTile, RestoreTile, EditorSheet (tabs: Icons/
                  Effects/Generic/Text/Image), ColorPanel (wheel+hex+RGB), HueSliderBar,
                  AssetsPanel, SymbolPicker, EmojiPicker, BarPaletteWindow, Onboarding
  Utilities/      SVG rasterization (via NSImage/CoreGraphics or bundled renderer), extensions
  Resources/      Base folder artwork (recreated, original), bundled asset catalogs
```

Key technical notes:

- **Base folder artwork**: draw our own macOS-style folder silhouette (vector, layered front/back panels) so we can tint hue/saturation programmatically (Core Image hue rotate on a blue master, or template layers colored directly). Must look native at all sizes.
- **Tinting**: HSB shift of the stock folder look; gradients = two-stop linear over the folder mask.
- **Stamp/emboss**: use the overlay image's luminance as a mask; render darkened/lightened folder color with inner shadow for engraved look.
- **Smart Restore**: store the pre-existing icon (if any) in Application Support keyed by folder path + inode before overwriting.
- **Emoji/symbol catalogs**: bundle Twemoji SVGs + Lucide/Phosphor SVGs (licenses in Assets/licenses). SF Symbols come free via `NSImage(systemSymbolName:)`.
- **Menu-bar Bar**: `NSStatusItem` + borderless floating `NSPanel` hosting a compact SwiftUI grid; status item itself is a drop target. Launch dev builds only via `open` on the bundle (see /Users/sam/Claude/CLAUDE.md menu-bar trap).

## Build phases (subagent plan)

Phase 0 — Scaffold (Opus): XcodeGen project, app target, entitlements, empty windows, CI-able `scripts/build.sh`.
Phase 1 — Rendering engine (Opus): FolderIconRenderer + unit tests (golden images). The hard part.
Phase 2 — Models & persistence (Sonnet): Style/Asset Codable, AssetStore, autosave, import/export documents.
Phase 3 — Main UI (Opus): style grid, tiles, toolbar with hue slider, drag-and-drop apply, Restore tile.
Phase 4 — Editor (Opus): editor sheet with all tabs, color panel, transforms, effects.
Phase 5 — Pickers & catalogs (Sonnet): symbol/emoji pickers with search, SVG rasterization pipeline.
Phase 6 — Services (Sonnet): IconApplier, SmartRestore, tags, .icns/.iconset export.
Phase 7 — Folderist Bar (Sonnet): status item + mini palette.
Phase 8 — Polish (Sonnet): onboarding, app icon, help, QA pass.

Phases 1–2 parallel after 0; 3–4 after 1+2; 5–7 parallel; integration + polish last.
