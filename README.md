# Folderist

A macOS app for generating and applying custom folder icons. Drop folders in, pick a color (or gradient), stamp an SF Symbol / emoji / custom image / text on top, preview live, and apply with one click.

## Status

Planning phase. See [docs/FEATURES.md](docs/FEATURES.md) for the full feature spec and [docs/PLAN.md](docs/PLAN.md) for architecture.

## Layout

- `Folderist/` — app source (SwiftUI)
  - `App/` — app entry, main window
  - `Views/` — UI (steps, pickers, preview)
  - `Models/` — design state, presets
  - `Services/` — icon application (NSWorkspace), persistence
  - `Rendering/` — folder icon compositing engine
  - `Utilities/` — helpers
  - `Resources/` — bundled resources
- `FolderistTests/` — unit tests
- `Assets/` — bundled asset packs (emoji, icons) + licenses
- `docs/` — planning and research
- `scripts/` — build/run helpers
