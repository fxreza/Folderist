import AppKit
import UniformTypeIdentifiers

/// The side-effecting operations the main window performs on folders and
/// files: applying a style, restoring, exporting, and the `NSOpenPanel` /
/// `NSSavePanel` plumbing behind the toolbar and menu commands.
///
/// Kept out of the views so the SwiftUI layer stays declarative and so the
/// exact same code path runs whether an action was triggered by a drop, a
/// toolbar button, a context menu or a menu-bar command.
enum StyleActions {

    // MARK: Apply / restore

    /// Full apply pipeline for one style over many folders:
    /// Smart Restore snapshot → multi-representation render → set icon.
    ///
    /// Finder color tags are deliberately *not* part of this pipeline any
    /// more (the feature was removed from the UI); `TagService` survives
    /// unused so the capability can come back without re-deriving it.
    @discardableResult
    static func apply(style: Style, to urls: [URL]) -> Int {
        let folders = urls.filter(isExistingDirectory)
        guard !folders.isEmpty else { return 0 }
        let services = AppServices.shared
        let image = FolderIconRenderer.renderMultiRepresentationImage(
            style: style, resources: services.renderResources)

        var applied = 0
        for url in folders {
            services.smartRestore.snapshotIfNeeded(for: url)
            if IconApplier.apply(image: image, to: url) { applied += 1 }
        }
        return applied
    }

    @discardableResult
    static func restore(urls: [URL]) -> Int {
        let folders = urls.filter(isExistingDirectory)
        guard !folders.isEmpty else { return 0 }
        let store = AppServices.shared.smartRestore
        var restored = 0
        for url in folders where store.restore(url: url) { restored += 1 }
        return restored
    }

    static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    // MARK: Panels

    /// Folder chooser used by the apply ▶ button and "Apply to Folders…".
    static func chooseFolders(prompt: String = "Apply") -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        panel.message = "Choose the folders to \(prompt.lowercased())."
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .pdf]
        panel.prompt = "Choose"
        panel.message = "Choose an image to place on the folder."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Destination folder chooser used by "Export All Icons…".
    static func chooseDestinationFolder(prompt: String = "Export") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = "Choose a folder to write the .icns files into."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseSaveURL(suggestedName: String, contentType: UTType?) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if let contentType { panel.allowedContentTypes = [contentType] }
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Export — .icns only

    /// `.icns` is a registered system type; fall back to `.data` on the
    /// (theoretical) machine where the declaration is missing.
    static let icnsType: UTType = UTType(filenameExtension: "icns") ?? .data

    /// Renders `style` and writes a compiled `.icns` at `url`.
    static func writeICNS(style: Style, to url: URL) throws {
        let images = FolderIconRenderer.renderIconSet(
            style: style, resources: AppServices.shared.renderResources)
        try ExportService.writeICNS(images: images, to: url)
    }

    /// "Export This Icon…" — asks for a destination, then writes one `.icns`.
    static func exportIcon(style: Style, suggestedName: String? = nil) {
        let base = fileNameBase(suggestedName ?? style.name)
        guard let url = chooseSaveURL(suggestedName: "\(base).icns",
                                      contentType: icnsType) else { return }
        do {
            try writeICNS(style: style, to: url)
        } catch {
            report(error, title: "Export failed")
        }
    }

    /// "Export All Icons…" — creates a uniquely-named "Folderist Icons"
    /// subfolder inside `directory` (appending " 2", " 3", … if one already
    /// exists there) and writes every `(style, name)` pair into it as
    /// `<name>.icns`, de-duplicating names so two styles called the same
    /// thing don't overwrite each other. Reveals the created subfolder in
    /// Finder when at least one file was written.
    /// Returns the number of files written.
    @discardableResult
    static func exportAllIcons(_ items: [(style: Style, name: String)], to directory: URL) -> Int {
        let destination: URL
        do {
            destination = try uniqueSubfolder(named: "Folderist Icons", in: directory)
        } catch {
            report(error, title: "Export failed")
            return 0
        }

        var used: Set<String> = []
        var written = 0
        var firstError: Error?

        for item in items {
            var base = fileNameBase(item.name)
            if used.contains(base.lowercased()) {
                var suffix = 2
                while used.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
                base = "\(base) \(suffix)"
            }
            used.insert(base.lowercased())
            do {
                try writeICNS(style: item.style,
                              to: destination.appendingPathComponent("\(base).icns"))
                written += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError, written == 0 {
            report(firstError, title: "Export failed")
        }
        if written > 0 {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
        return written
    }

    /// Creates a new subfolder called `name` inside `directory`, appending
    /// " 2", " 3", … to the name until it doesn't collide with an existing
    /// item, so repeated exports never merge into or overwrite one another.
    private static func uniqueSubfolder(named name: String, in directory: URL) throws -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }

    // MARK: Drag out

    /// Root of the scratch area drag-out `.icns` files are written into.
    private static var dragDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderistDrag", isDirectory: true)
    }

    /// Renders `style` into a temporary `.icns` so the tile can be dragged
    /// straight into Finder as a real icon file (#20 — this used to hand out
    /// a PNG). Each drag gets its own subdirectory so the visible file keeps
    /// the style's name even when two styles share it.
    static func temporaryICNS(for style: Style, name: String? = nil) -> URL? {
        let dir = dragDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(fileNameBase(name ?? style.name)).icns")
            try writeICNS(style: style, to: url)
            return url
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }

    /// Deletes drag scratch files left behind by previous runs (anything
    /// older than a day). Called once at launch from `FolderistApp`.
    static func cleanUpOldDragFiles(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dragDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let stamp = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
            if stamp < cutoff { try? fm.removeItem(at: entry) }
        }
    }

    // MARK: Importing dropped icon/image files

    /// True when `url`'s extension is a UTI that conforms to `.image` — the
    /// test for "readable image file" used by the grid's empty-area import
    /// (`.icns` is handled separately, since it needs its largest
    /// representation extracted rather than a straight byte copy).
    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// PNG bytes of `url`'s largest representation — used when importing a
    /// dropped `.icns` file as a new style's image overlay. `nil` if the file
    /// can't be decoded as an icon/image at all.
    static func pngData(fromIconFile url: URL) -> Data? {
        guard let icon = NSImage(contentsOf: url) else { return nil }
        let largest = icon.representations
            .map { max($0.pixelsWide, $0.pixelsHigh) }
            .max() ?? 0
        let pixelSize = max(256, min(1024, largest))
        return try? ExportService.pngData(for: icon, pixelSize: pixelSize)
    }

    /// Filesystem-safe base name ("Folder" when empty).
    static func fileNameBase(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Folder" : cleaned
    }

    // MARK: Errors

    static func report(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

    /// Plain informational alert (e.g. "these folders had no custom icon").
    static func notify(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// Modal yes/no used for destructive actions (deleting a style/asset).
    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
