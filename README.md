# Folderist

A macOS app for generating and applying custom folder icons. Drop folders in, pick a color (or gradient), stamp an SF Symbol / emoji / custom image / text on top, preview live, and apply with one click.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

## Install

Download `Folderist.dmg` from the [latest release](https://github.com/fxreza/Folderist/releases/latest), open it, and drag **Folderist** to your Applications folder.

The build is ad-hoc signed rather than notarized, so the first launch needs Gatekeeper's consent: right-click the app and choose **Open**, then confirm.

## Features

- 4-column grid of reusable folder styles; add, rename, duplicate, copy/paste and delete tiles.
- Overlays: SF Symbols, emoji, your own text, or an imported image, with move / scale / rotate and align controls.
- Full folder recoloring, including the stock macOS blue as a one-click reset.
- Apply to any number of folders at once, or drag a folder straight onto a tile.
- Export any style, or every style, as `.icns` — or drag a tile out to Finder.
- Restore tile to put the original icons back.

## Build from source

Requires macOS 14+ and a Swift 5.9 toolchain (Xcode 15 or later).

```bash
./scripts/build.sh      # release build, assembles build/Folderist.app
./scripts/run_app.sh    # launch the assembled bundle
./scripts/make-dmg.sh   # package build/Folderist.app as build/Folderist.dmg
```

## Layout

- `Folderist/` — app source (SwiftUI)
  - `App/` — app entry, main window
  - `Views/` — UI (grid, editor, pickers, help)
  - `Models/` — design state, presets
  - `Services/` — icon application (NSWorkspace), persistence
  - `Rendering/` — folder icon compositing engine
  - `Resources/` — bundled resources
- `FolderistTests/` — unit tests
- `Assets/` — bundled asset packs (emoji, icons) + licenses
- `docs/` — planning and research
- `scripts/` — build/run/package helpers

## Third-party assets

The bundled icon and emoji packs keep their own licenses. See [Assets/licenses/ATTRIBUTIONS.md](Assets/licenses/ATTRIBUTIONS.md).
