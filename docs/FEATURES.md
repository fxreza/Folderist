# Folderist — Feature Specification (v1 target)

Modeled on FolderMarker 4.0 by ImageStudio Pro ($7.99, macOS 10.11+). Same feature set and UI structure; original code, original openly-licensed assets, our own branding. Items marked **[extra]** are additions that fix documented FolderMarker complaints; everything else is feature parity.

## 1. Core model: Styles, Assets, drag-and-drop

- **Style** = a saved folder-icon design (base color/gradient + overlay + effects). Rendered as a large folder tile in the main grid.
- **Asset** = a named collection of up to 40 editable Styles. Unlimited Assets; quick switching; one locked "Main Asset" by default. Bundled starter assets: Basic Colors, Symbols, Emoji, Alphabet, Numbers, Work, Text, Images, Misc.
- **Apply by drag & drop**: drag Finder folders onto a style tile (or select folders + press apply ▶). Batch: multiple folders at once.
- **Restore tile**: drop a folder on it to revert to the default macOS folder icon.
- **Smart Restore**: before applying, snapshot the folder's existing custom icon so Restore brings back the original (not just the system default).
- Apply to folder **aliases** (works on modern macOS — fixing FolderMarker's known Big Sur regression) **[extra: actually working]**.

## 2. Editor (per-style)

Popover/sheet over the grid with a big live folder preview. Tabs: **Icons | Effects | Generic | Text** (+ image controls when an image is present).

- **Color**: color wheel + brightness/saturation triangle, hue slider (rainbow strip in the toolbar, live), Color Shuffle (random), hex + RGB fields, eyedropper. Two-color **gradients**.
- **Overlays** — combinable: a style can have an icon/emoji/image overlay, a text overlay, or **both at once** (icon + text), or text only:
  - **Symbols**: bundled monochrome glyph library (Lucide + Phosphor, ~4,800 icons) + all ~6,000 SF Symbols via system APIs.
  - **Emoji**: full emoji set (Twemoji, ~4,000).
  - **Text**: short text on the folder, font family picker + face picker (regular, bold, italic, condensed, every installed face), **size slider** (auto-fit option so text scales to fit the folder), embossed or flat rendering, text color.
  - **Images** (user-imported, drag & drop) with 4 compositing modes:
    - *Image Fill* — image fills the folder silhouette
    - *Image Over* — image composited on top of the folder
    - *Image Stamp* — B/W image engraved/stamped into the folder color
    - *Image Only* — image replaces the folder icon entirely
- **Transforms**: position (drag), scale (slider/pinch), rotation (handle/gesture) for overlays.
- **Effects**: shadow, fill, opacity, inner stroke, outer stroke, emboss.
- Search field in symbol/emoji pickers.
- **[extra]** Text on top of a custom base image (a documented FolderMarker gap).
- **[extra]** Alternate base folder shapes/colors of the modern macOS folder (requested by users; FolderMarker only has the one silhouette).

## 3. Style management

- Save, rename **[extra: named tiles]**, replace, copy/duplicate styles between slots; reorder in grid.
- Export/import single styles; drag-and-drop export/import of whole Assets (file format: a Folderist document).
- Optional iCloud Drive sync of assets/settings across Macs.
- Export a style as **.icns** and **.iconset** (and PNG **[extra]**).

## 4. Finder integration

- Applies icons directly via NSWorkspace (no Finder extension needed).
- Optionally set the matching macOS **color tag** when applying a color; folder labels as additional tags.
- Right-click Finder context menu (Services / Finder extension) — stretch goal for v1.

## 5. App-level

- Dark, compact utility UI matching FolderMarker's layout: toolbar (export, share, iCloud, tags, hue slider, apply ▶, emoji, symbols, T, image, +/−), style grid, floating Assets / Color / Symbols panels.
- Menus: File, Edit, Format, Settings, Tags, Labels, Window, Help.
- Autosave. Retina-ready rendering at all icon sizes (16→1024 px).
- **[extra]** Onboarding/in-app help (FolderMarker's #1 complaint is zero documentation).
- Localization-ready (English first).
- macOS 14+ (Sonoma), Apple silicon + Intel, sandboxed, no data collection.

## Explicitly out of scope for v1

- Touch Bar support (hardware is discontinued).
- Subscription/licensing — build free/unrestricted for now.
