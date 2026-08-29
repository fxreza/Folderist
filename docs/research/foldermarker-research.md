# FolderMarker research summary

Full UI analysis: [ui-notes.md](ui-notes.md). Screenshots: fm1–fm5.jpg.

- **FolderMarker** by Image Studio Production (seller Elena Drozhzhina), bundle `com.imagestudiopro.FolderMarker`, App Store id 1012940117. $7.99 one-time, no IAP/subscription/trial. v4.0 (2024-11-11), first release 2015. ~9 MB, min macOS 10.11. EN/FR/RU/ES. "No data collected."
- Feature evolution: v1.2 Bar (menu-bar) → v1.2.2 color tags → v1.3 Finder context menu → v2.0 editor + icon/emoji/symbol collections → v2.5 color shuffle + wheel → v3.0 iCloud, Touch Bar, text, ICNS export → v3.1 rotation gesture, shadow/stroke, Smart Restore → v4.0 Assets system, iconset export, Sequoia/Apple silicon.
- Technique (inferred): direct `NSWorkspace.setIcon` on dropped folders; Smart Restore snapshots the pre-existing icon; no Finder Sync extension; iCloud Drive used only for user-invoked asset sync. Alias support broke in Big Sur and was never fixed (still caveated).
- User complaints (= our opportunities): (1) no documentation/onboarding at all — the #1 complaint for years; (2) can't combine a custom base image with text on top; (3) only one folder silhouette, no alternate shapes; (4) fixed built-in icon library, users want niche packs; (5) can't name/label preset tiles; (6) alias regression.
- Praise: drag-drop simplicity, breadth of symbols/effects, preset saving vs one-shot competitors, speed, privacy, iCloud sync.
- Risk note: macOS 26 Tahoe added native folder customization (color + emoji/symbol on folders via Finder) — a clone should differentiate on images/text/effects/styles/batch/export, which the native feature lacks.
- Unrelated products to ignore: "Folder Marker" for Windows (foldermarker.com), "Folderizer" by Eugenio Keller (id6480047256).
