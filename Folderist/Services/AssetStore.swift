import Foundation
import Combine
import CryptoKit

/// Owns the persisted `Library` (Assets + Styles), autosaves it to disk,
/// and provides CRUD + duplication/copy operations plus import/export of
/// `.folderist` documents (see `FolderistDocument.swift`) and image storage.
///
/// Not actor-isolated: callers on macOS apps are expected to use this from
/// the main thread (it backs SwiftUI via `ObservableObject`), but the disk
/// I/O itself happens on a private serial queue.
final class AssetStore: ObservableObject {

    enum StoreError: Error, Equatable {
        case assetNotFound
        case assetLocked
        case styleNotFound
        case styleLimitReached
        case syncDirectoryNotSet
        case emptyDocument
    }

    @Published private(set) var library: Library

    /// When set, `exportAssetToSyncDirectory` / `importAllFromSyncDirectory`
    /// read and write `.folderist` documents here instead of failing.
    /// Point this at a folder inside iCloud Drive (already downloaded via
    /// the Files app / `NSMetadataQuery` elsewhere) to get simple,
    /// CloudKit-free syncing: every Mac pointed at the same folder sees the
    /// same documents.
    var syncDirectoryOverride: URL?

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let libraryFileURL: URL

    private let autosaveQueue = DispatchQueue(label: "com.folderist.assetstore.autosave")
    private var pendingSave: DispatchWorkItem?
    private let autosaveDelay: TimeInterval

    // MARK: Init

    init(rootDirectory: URL? = nil, autosaveDelay: TimeInterval = 0.5, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.autosaveDelay = autosaveDelay
        let root = rootDirectory ?? AssetStore.defaultRootDirectory()
        self.rootDirectory = root
        self.imagesDirectory = root.appendingPathComponent("images", isDirectory: true)
        self.libraryFileURL = root.appendingPathComponent("library.json")

        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: libraryFileURL),
           let loaded = try? JSONDecoder().decode(Library.self, from: data) {
            self.library = loaded
        } else {
            self.library = AssetStore.seedLibrary()
        }
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Folderist", isDirectory: true)
    }

    // MARK: Persistence

    /// Writes the library to disk immediately, cancelling any pending
    /// debounced autosave.
    func saveNow() throws {
        pendingSave?.cancel()
        pendingSave = nil
        let data = try AssetStore.jsonEncoder.encode(library)
        try data.write(to: libraryFileURL, options: .atomic)
    }

    /// Applies a mutation to the library and schedules a debounced autosave.
    /// Exists so other files in this module (e.g. import/export) can mutate
    /// `library` without exposing a public setter on the `@Published` property.
    func mutateLibrary(_ body: (inout Library) -> Void) {
        body(&library)
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            try? self?.saveNow()
        }
        pendingSave = item
        autosaveQueue.asyncAfter(deadline: .now() + autosaveDelay, execute: item)
    }

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    // MARK: Asset CRUD

    @discardableResult
    func addAsset(name: String) -> Asset {
        let asset = Asset(name: name)
        library.assets.append(asset)
        scheduleAutosave()
        return asset
    }

    func renameAsset(_ id: UUID, to newName: String) throws {
        guard let idx = library.assets.firstIndex(where: { $0.id == id }) else { throw StoreError.assetNotFound }
        library.assets[idx].name = newName
        scheduleAutosave()
    }

    func deleteAsset(_ id: UUID) throws {
        guard let idx = library.assets.firstIndex(where: { $0.id == id }) else { throw StoreError.assetNotFound }
        if library.assets[idx].isLocked { throw StoreError.assetLocked }
        library.assets.remove(at: idx)
        if library.selectedAssetID == id {
            library.selectedAssetID = library.assets.first?.id
        }
        scheduleAutosave()
    }

    func reorderAssets(from source: IndexSet, to destination: Int) {
        library.assets.moveElements(fromOffsets: source, toOffset: destination)
        scheduleAutosave()
    }

    func selectAsset(_ id: UUID?) {
        library.selectedAssetID = id
        scheduleAutosave()
    }

    // MARK: Style CRUD

    @discardableResult
    func addStyle(_ style: Style = Style(), to assetID: UUID) throws -> Style {
        guard let idx = library.assets.firstIndex(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        guard library.assets[idx].styles.count < Asset.maxStyles else { throw StoreError.styleLimitReached }
        library.assets[idx].styles.append(style)
        scheduleAutosave()
        return style
    }

    func renameStyle(_ styleID: UUID, in assetID: UUID, to newName: String) throws {
        try withStyle(styleID, in: assetID) { $0.name = newName }
    }

    /// Full replace — used by the editor to write back all edits at once.
    func updateStyle(_ style: Style, in assetID: UUID) throws {
        try withStyle(style.id, in: assetID) { $0 = style }
    }

    func deleteStyle(_ styleID: UUID, from assetID: UUID) throws {
        guard let aIdx = library.assets.firstIndex(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        guard let sIdx = library.assets[aIdx].styles.firstIndex(where: { $0.id == styleID }) else { throw StoreError.styleNotFound }
        library.assets[aIdx].styles.remove(at: sIdx)
        scheduleAutosave()
    }

    func reorderStyles(in assetID: UUID, from source: IndexSet, to destination: Int) throws {
        guard let aIdx = library.assets.firstIndex(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        library.assets[aIdx].styles.moveElements(fromOffsets: source, toOffset: destination)
        scheduleAutosave()
    }

    /// Duplicates a style in place, right after the original, within the same asset.
    @discardableResult
    func duplicateStyle(_ styleID: UUID, in assetID: UUID) throws -> Style {
        guard let aIdx = library.assets.firstIndex(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        guard let sIdx = library.assets[aIdx].styles.firstIndex(where: { $0.id == styleID }) else { throw StoreError.styleNotFound }
        guard library.assets[aIdx].styles.count < Asset.maxStyles else { throw StoreError.styleLimitReached }
        var copy = library.assets[aIdx].styles[sIdx]
        copy.id = UUID()
        if !copy.name.isEmpty { copy.name += " copy" }
        library.assets[aIdx].styles.insert(copy, at: sIdx + 1)
        scheduleAutosave()
        return copy
    }

    /// Copies a style from one asset to another (appended at the end of the destination).
    @discardableResult
    func copyStyle(_ styleID: UUID, from sourceAssetID: UUID, to destinationAssetID: UUID) throws -> Style {
        guard let srcIdx = library.assets.firstIndex(where: { $0.id == sourceAssetID }) else { throw StoreError.assetNotFound }
        guard let styleIdx = library.assets[srcIdx].styles.firstIndex(where: { $0.id == styleID }) else { throw StoreError.styleNotFound }
        guard let dstIdx = library.assets.firstIndex(where: { $0.id == destinationAssetID }) else { throw StoreError.assetNotFound }
        guard library.assets[dstIdx].styles.count < Asset.maxStyles else { throw StoreError.styleLimitReached }
        var copy = library.assets[srcIdx].styles[styleIdx]
        copy.id = UUID()
        library.assets[dstIdx].styles.append(copy)
        scheduleAutosave()
        return copy
    }

    private func withStyle(_ styleID: UUID, in assetID: UUID, _ mutate: (inout Style) -> Void) throws {
        guard let aIdx = library.assets.firstIndex(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        guard let sIdx = library.assets[aIdx].styles.firstIndex(where: { $0.id == styleID }) else { throw StoreError.styleNotFound }
        mutate(&library.assets[aIdx].styles[sIdx])
        scheduleAutosave()
    }

    // MARK: Images

    /// Copies the file at `url` into the store's images directory, named by
    /// its content hash (so re-importing the same bytes is a no-op) plus its
    /// original extension. Returns the `fileName` to store on
    /// `GraphicOverlay.image`.
    @discardableResult
    func importImage(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return try storeImageData(data, preferredExtension: url.pathExtension)
    }

    @discardableResult
    func storeImageData(_ data: Data, preferredExtension: String) throws -> String {
        let hash = AssetStore.sha256Hex(data)
        let ext = preferredExtension.isEmpty ? "png" : preferredExtension
        let fileName = "\(hash).\(ext)"
        let dest = imagesDirectory.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: dest.path) {
            try data.write(to: dest)
        }
        return fileName
    }

    func imageURL(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    func imageData(for fileName: String) -> Data? {
        try? Data(contentsOf: imageURL(for: fileName))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Seed data

    /// One unlocked asset holding every starter style.
    ///
    /// The app shows a single grid, so the library seeds a single **unlocked**
    /// asset: the starter designs plus a rainbow of plain solid colors merged
    /// into the same collection. Unlocked matters because `isLocked` blocks
    /// asset deletion, and there is no longer any UI to switch away from a
    /// locked asset.
    static func seedLibrary() -> Library {
        var main = Asset(name: "Main Asset")

        main.styles.append(Style(
            name: "Ocean Gradient",
            fill: .gradient(
                StyleColor(red: 0.157, green: 0.517, blue: 0.925),
                StyleColor(red: 0.086, green: 0.788, blue: 0.717),
                angleDegrees: 45
            )
        ))

        let symbols: [(String, String)] = [
            ("Star", "star.fill"),
            ("Heart", "heart.fill"),
            ("Gear", "gear"),
            ("Bolt", "bolt.fill"),
            ("Flag", "flag.fill"),
        ]
        for (name, symbol) in symbols {
            main.styles.append(Style(name: name, fill: .solid(.folderBlue), graphic: .sfSymbol(name: symbol)))
        }

        main.styles.append(Style(
            name: "Party",
            fill: .solid(StyleColor(red: 0.945, green: 0.769, blue: 0.059)),
            graphic: .emoji("🎉")
        ))

        main.styles.append(Style(
            name: "Label",
            fill: .solid(StyleColor(red: 0.20, green: 0.20, blue: 0.22)),
            text: TextOverlay(text: "TXT")
        ))

        let rainbow: [(String, StyleColor)] = [
            ("Red", StyleColor(red: 0.937, green: 0.325, blue: 0.314)),
            ("Orange", StyleColor(red: 1.0, green: 0.596, blue: 0.0)),
            ("Yellow", StyleColor(red: 0.988, green: 0.804, blue: 0.235)),
            ("Green", StyleColor(red: 0.298, green: 0.686, blue: 0.314)),
            ("Blue", StyleColor(red: 0.259, green: 0.522, blue: 0.957)),
            ("Purple", StyleColor(red: 0.607, green: 0.349, blue: 0.713)),
            ("Pink", StyleColor(red: 0.914, green: 0.427, blue: 0.686)),
            ("Gray", StyleColor(red: 0.596, green: 0.596, blue: 0.596)),
        ]
        main.styles.append(contentsOf: rainbow.map { Style(name: $0.0, fill: .solid($0.1)) })

        return Library(assets: [main], selectedAssetID: main.id)
    }
}

extension Array {
    /// Moves the elements at `source` to just before `destination`, matching
    /// the semantics of SwiftUI's `List`/`ForEach` `.onMove(perform:)`
    /// callback — reimplemented here (rather than calling SwiftUI's
    /// `move(fromOffsets:toOffset:)`) so the Services layer never has to
    /// link against SwiftUI.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let elementsToMove = source.map { self[$0] }
        for index in source.sorted(by: >) {
            remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let adjustedDestination = Swift.max(0, Swift.min(destination - removedBeforeDestination, count))
        insert(contentsOf: elementsToMove, at: adjustedDestination)
    }
}
