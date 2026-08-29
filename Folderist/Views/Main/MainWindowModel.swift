import AppKit
import Combine
import SwiftUI

/// UI state for the main window: which tile is selected, which panels are
/// open, what the editor is editing, and the style clipboard.
///
/// A shared instance exists because `FolderistApp`'s `.commands` (the menu
/// bar) has to drive the same window state as the toolbar, and menu commands
/// cannot reach a `@StateObject` that lives inside the window's view tree.
/// Folderist is a single-main-window app, so one shared model is the honest
/// model of the app rather than a shortcut.
final class MainWindowModel: ObservableObject {
    static let shared = MainWindowModel()

    /// Style catalog for the symbol/emoji pickers — loaded once, since
    /// `CatalogIndex.init` walks the bundled asset packs from disk.
    let catalogIndex = CatalogIndex()

    @Published var selectedStyleID: UUID?
    @Published var editing: EditorTarget?
    @Published var renamingStyleID: UUID?
    /// Copy/Paste Style, kept in-app (a `Style` has no pasteboard type).
    @Published var styleClipboard: Style?

    /// What the editor sheet is editing, plus which tab it opened on.
    struct EditorTarget: Identifiable, Equatable {
        var styleID: UUID
        var assetID: UUID
        var initialTab: EditorTab
        var id: UUID { styleID }
    }

    private var store: AssetStore { AppServices.shared.assetStore }

    // MARK: Derived model access

    /// The one asset the grid shows. The app no longer exposes an asset
    /// switcher (#9): `AssetStore` still stores a `Library` of assets, but the
    /// UI always works on the selected one, falling back to the first.
    var selectedAsset: Asset? {
        let library = store.library
        return library.assets.first { $0.id == library.selectedAssetID } ?? library.assets.first
    }

    var selectedAssetID: UUID? { selectedAsset?.id }

    var selectedStyle: Style? {
        guard let id = selectedStyleID else { return nil }
        return selectedAsset?.styles.first { $0.id == id }
    }

    /// Caption for a tile: the style's name, or "Folder N" for unnamed ones
    /// (matching FolderMarker's "Folder 7" placeholder captions).
    func caption(for style: Style) -> String {
        if !style.name.isEmpty { return style.name }
        let index = (selectedAsset?.styles.firstIndex { $0.id == style.id }).map { $0 + 1 } ?? 1
        return "Folder \(index)"
    }

    // MARK: Mutation helpers

    /// Applies `mutate` to the selected style and writes it back through the
    /// store (the single funnel every live edit goes through).
    func mutateSelectedStyle(_ mutate: (inout Style) -> Void) {
        guard let assetID = selectedAssetID, var style = selectedStyle else { return }
        mutate(&style)
        try? store.updateStyle(style, in: assetID)
    }

    func select(_ styleID: UUID?) {
        selectedStyleID = styleID
    }

    func openEditor(styleID: UUID, tab: EditorTab = .icons) {
        guard let assetID = selectedAssetID else { return }
        selectedStyleID = styleID
        editing = EditorTarget(styleID: styleID, assetID: assetID, initialTab: tab)
    }

    /// Opens the editor on the current selection, creating a style first if
    /// the grid has none selected yet.
    func openEditorOnSelection(tab: EditorTab = .icons) {
        if let id = selectedStyleID {
            openEditor(styleID: id, tab: tab)
        } else if let created = addStyle() {
            openEditor(styleID: created.id, tab: tab)
        }
    }

    // MARK: Style CRUD

    @discardableResult
    func addStyle(_ style: Style = Style()) -> Style? {
        guard let assetID = selectedAssetID else { return nil }
        do {
            let created = try store.addStyle(style, to: assetID)
            selectedStyleID = created.id
            return created
        } catch {
            StyleActions.report(error, title: "Couldn't add a style")
            return nil
        }
    }

    func duplicateSelectedStyle() {
        guard let assetID = selectedAssetID, let id = selectedStyleID else { return }
        do {
            let copy = try store.duplicateStyle(id, in: assetID)
            selectedStyleID = copy.id
        } catch {
            StyleActions.report(error, title: "Couldn't duplicate the style")
        }
    }

    func deleteSelectedStyle(confirm: Bool = true) {
        guard let assetID = selectedAssetID, let style = selectedStyle else { return }
        if confirm {
            let ok = StyleActions.confirm(
                title: "Delete “\(caption(for: style))”?",
                message: "The style is removed from this asset. Folders already marked with it keep their icons.",
                confirmTitle: "Delete")
            guard ok else { return }
        }
        let styles = selectedAsset?.styles ?? []
        let index = styles.firstIndex { $0.id == style.id }
        try? store.deleteStyle(style.id, from: assetID)
        let remaining = selectedAsset?.styles ?? []
        if let index {
            selectedStyleID = remaining.indices.contains(index) ? remaining[index].id
                : remaining.last?.id
        } else {
            selectedStyleID = remaining.first?.id
        }
    }

    func pasteStyle() {
        guard let clip = styleClipboard else { return }
        var copy = clip
        copy.id = UUID()
        addStyle(copy)
    }

    func copySelectedStyle() {
        styleClipboard = selectedStyle
    }

    // MARK: Export (#11/#20 — .icns only)

    var hasStyles: Bool { !(selectedAsset?.styles.isEmpty ?? true) }

    /// "Export This Icon…" — the selected tile, to a chosen `.icns` file.
    func exportSelectedStyle() {
        guard let style = selectedStyle else { NSSound.beep(); return }
        StyleActions.exportIcon(style: style, suggestedName: caption(for: style))
    }

    /// "Export All Icons…" — every tile in the grid, into a chosen folder,
    /// each as `<style name or "Folder N">.icns`.
    func exportAllStyles() {
        let styles = selectedAsset?.styles ?? []
        guard !styles.isEmpty else { NSSound.beep(); return }
        guard let directory = StyleActions.chooseDestinationFolder() else { return }
        let items = styles.map { (style: $0, name: caption(for: $0)) }
        StyleActions.exportAllIcons(items, to: directory)
    }

    // MARK: Importing dropped icon/image files (#12)

    /// Turns `.icns` or image files dropped on the grid's empty area into new
    /// editable styles, one per file. `.icns` files contribute their largest
    /// representation; other readable image files are copied as-is. Folders
    /// dropped here are ignored — only the tiles themselves accept folders,
    /// for apply/restore. Files that aren't `.icns` or a readable image are
    /// skipped and reported.
    func importStylesFromIconFiles(_ urls: [URL]) {
        var skipped: [String] = []
        var lastCreated: Style?

        for url in urls {
            do {
                let fileName: String
                if url.pathExtension.lowercased() == "icns" {
                    guard let data = StyleActions.pngData(fromIconFile: url) else {
                        skipped.append(url.lastPathComponent)
                        continue
                    }
                    fileName = try store.storeImageData(data, preferredExtension: "png")
                } else if StyleActions.isImageFile(url) {
                    fileName = try store.importImage(from: url)
                } else {
                    skipped.append(url.lastPathComponent)
                    continue
                }
                let style = Style(name: url.deletingPathExtension().lastPathComponent,
                                  graphic: .image(fileName: fileName, mode: .only))
                lastCreated = addStyle(style)
            } catch {
                StyleActions.report(error, title: "Couldn't import “\(url.lastPathComponent)”")
            }
        }

        if let lastCreated { selectedStyleID = lastCreated.id }

        if !skipped.isEmpty {
            let names = skipped.prefix(8).joined(separator: ", ")
            let more = skipped.count > 8 ? " and \(skipped.count - 8) more" : ""
            StyleActions.notify(
                title: skipped.count == 1 ? "That file couldn't be imported"
                                          : "\(skipped.count) files couldn't be imported",
                message: "\(names)\(more) aren't .icns files or readable images.")
        }
    }

    // MARK: Apply

    /// File ▸ Apply to Folders… (also the tile context menu) — pick folders,
    /// then apply the current selection to them.
    func applySelectedStyleToChosenFolders() {
        guard let style = selectedStyle else { NSSound.beep(); return }
        let urls = StyleActions.chooseFolders()
        guard !urls.isEmpty else { return }
        StyleActions.apply(style: style, to: urls)
    }
}
