import AppKit
import CryptoKit

/// Snapshots a folder's existing custom icon (if any) before Folderist
/// overwrites it, so `restore(url:)` can bring back exactly what was there —
/// not just the generic macOS folder icon.
///
/// Detection: a folder has a *custom* icon (as opposed to the generic
/// per-type icon Finder synthesizes on the fly) iff it contains the hidden
/// resource file named `Icon\r` (Icon, then a literal carriage return). This
/// is the same mechanism Finder itself uses and is far more reliable than
/// trying to diff `NSWorkspace.shared.icon(forFile:)` against the generic
/// icon image.
final class SmartRestoreStore {

    private let fileManager: FileManager
    private let snapshotsDirectory: URL
    private let indexURL: URL
    private var index: [String: String] // folder path -> snapshot key (sha256 of path)

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = rootDirectory ?? AssetStore.defaultRootDirectory()
        self.snapshotsDirectory = root.appendingPathComponent("restore", isDirectory: true)
        self.indexURL = snapshotsDirectory.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.index = decoded
        } else {
            self.index = [:]
        }
    }

    /// True if `url` (a folder) currently carries a Finder custom icon.
    func hasCustomIcon(at url: URL) -> Bool {
        let iconFile = url.appendingPathComponent("Icon\r")
        return fileManager.fileExists(atPath: iconFile.path)
    }

    /// Call this immediately before applying a new icon. No-ops if the
    /// folder has no custom icon to preserve.
    @discardableResult
    func snapshotIfNeeded(for url: URL) -> Bool {
        guard hasCustomIcon(at: url) else { return false }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        guard let tiff = image.tiffRepresentation else { return false }
        let key = SmartRestoreStore.snapshotKey(for: url)
        let fileURL = snapshotFileURL(for: key)
        do {
            try tiff.write(to: fileURL)
        } catch {
            return false
        }
        index[url.path] = key
        saveIndex()
        return true
    }

    /// True if a snapshot exists for `url` (i.e. Restore will bring back a
    /// specific prior icon rather than just clearing to the system default).
    func hasSnapshot(for url: URL) -> Bool {
        index[url.path] != nil
    }

    /// Reapplies the snapshot for `url` if one exists (and deletes it after),
    /// otherwise falls back to clearing to the system default icon.
    @discardableResult
    func restore(url: URL) -> Bool {
        guard let key = index[url.path] else {
            return IconApplier.restoreDefault(url: url)
        }
        let fileURL = snapshotFileURL(for: key)
        defer {
            try? fileManager.removeItem(at: fileURL)
            index.removeValue(forKey: url.path)
            saveIndex()
        }
        guard let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) else {
            return IconApplier.restoreDefault(url: url)
        }
        return IconApplier.apply(image: image, to: url)
    }

    private func snapshotFileURL(for key: String) -> URL {
        snapshotsDirectory.appendingPathComponent("\(key).tiff")
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    static func snapshotKey(for url: URL) -> String {
        AssetStore.sha256Hex(Data(url.path.utf8))
    }
}
