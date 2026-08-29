import Foundation

/// On-disk `.folderist` document: a single Asset or a single Style, plus any
/// images its styles reference bundled inline as base64 (via `Data`'s
/// default `Codable` conformance) so the document is fully self-contained
/// and portable between Macs / through iCloud Drive / AirDrop.
struct FolderistDocument: Codable, Equatable {
    var formatVersion: Int = 1
    var asset: Asset?
    var style: Style?
    /// fileName (as referenced by `GraphicOverlay.image`) -> raw file bytes.
    var images: [String: Data] = [:]
}

extension AssetStore {

    // MARK: Building documents

    func exportDocument(assetID: UUID) throws -> FolderistDocument {
        guard let asset = library.assets.first(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        var doc = FolderistDocument()
        doc.asset = asset
        doc.images = collectImages(for: asset.styles)
        return doc
    }

    func exportDocument(styleID: UUID, in assetID: UUID) throws -> FolderistDocument {
        guard let asset = library.assets.first(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        guard let style = asset.styles.first(where: { $0.id == styleID }) else { throw StoreError.styleNotFound }
        var doc = FolderistDocument()
        doc.style = style
        doc.images = collectImages(for: [style])
        return doc
    }

    private func collectImages(for styles: [Style]) -> [String: Data] {
        var result: [String: Data] = [:]
        for style in styles {
            if case .image(let fileName, _)? = style.graphic, let data = imageData(for: fileName) {
                result[fileName] = data
            }
        }
        return result
    }

    // MARK: File I/O

    func writeDocument(_ doc: FolderistDocument, to url: URL) throws {
        let data = try AssetStore.jsonEncoder.encode(doc)
        try data.write(to: url, options: .atomic)
    }

    func readDocument(from url: URL) throws -> FolderistDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FolderistDocument.self, from: data)
    }

    @discardableResult
    func exportAsset(_ assetID: UUID, to url: URL) throws -> FolderistDocument {
        let doc = try exportDocument(assetID: assetID)
        try writeDocument(doc, to: url)
        return doc
    }

    @discardableResult
    func exportStyle(_ styleID: UUID, in assetID: UUID, to url: URL) throws -> FolderistDocument {
        let doc = try exportDocument(styleID: styleID, in: assetID)
        try writeDocument(doc, to: url)
        return doc
    }

    // MARK: Import (always assigns fresh UUIDs; images are re-deduped by hash)

    /// Imports a `.folderist` document.
    /// - An Asset document is appended to the library as a new Asset (new UUID, unlocked).
    /// - A Style document is appended to `intoAssetID` if given (merging into an existing
    ///   Asset), otherwise wrapped in a new "Imported" Asset.
    @discardableResult
    func importDocument(from url: URL, intoAssetID: UUID? = nil) throws -> Asset {
        let doc = try readDocument(from: url)

        var fileNameMap: [String: String] = [:]
        for (originalName, data) in doc.images {
            let ext = (originalName as NSString).pathExtension
            fileNameMap[originalName] = try storeImageData(data, preferredExtension: ext)
        }

        if let asset = doc.asset {
            var imported = asset
            imported.id = UUID()
            imported.isLocked = false
            imported.styles = asset.styles.map { remapStyle($0, fileNameMap: fileNameMap) }
            mutateLibrary { $0.assets.append(imported) }
            saveDebounced()
            return imported
        }

        guard let style = doc.style else { throw StoreError.emptyDocument }
        let remapped = remapStyle(style, fileNameMap: fileNameMap)

        if let targetID = intoAssetID, let idx = library.assets.firstIndex(where: { $0.id == targetID }) {
            guard library.assets[idx].styles.count < Asset.maxStyles else { throw StoreError.styleLimitReached }
            mutateLibrary { $0.assets[idx].styles.append(remapped) }
            saveDebounced()
            return library.assets[idx]
        }

        var wrapper = Asset(name: "Imported")
        wrapper.styles = [remapped]
        mutateLibrary { $0.assets.append(wrapper) }
        saveDebounced()
        return wrapper
    }

    private func remapStyle(_ style: Style, fileNameMap: [String: String]) -> Style {
        var copy = style
        copy.id = UUID()
        if case .image(let fileName, let mode)? = copy.graphic, let newName = fileNameMap[fileName] {
            copy.graphic = .image(fileName: newName, mode: mode)
        }
        return copy
    }

    // MARK: iCloud Drive sync (no CloudKit — just a shared folder the user points us at)

    @discardableResult
    func exportAssetToSyncDirectory(_ assetID: UUID) throws -> URL {
        guard let dir = syncDirectoryOverride else { throw StoreError.syncDirectoryNotSet }
        guard let asset = library.assets.first(where: { $0.id == assetID }) else { throw StoreError.assetNotFound }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(sanitizedFileName(asset.name)).folderist")
        try exportAsset(assetID, to: fileURL)
        return fileURL
    }

    /// Imports every `.folderist` document currently in `syncDirectoryOverride`
    /// that isn't already present (matched by asset name, since imports mint
    /// fresh UUIDs each time).
    @discardableResult
    func importAllFromSyncDirectory() throws -> [Asset] {
        guard let dir = syncDirectoryOverride else { throw StoreError.syncDirectoryNotSet }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let existingNames = Set(library.assets.map(\.name))
        var imported: [Asset] = []
        for file in files where file.pathExtension == "folderist" {
            guard let doc = try? readDocument(from: file), let assetName = doc.asset?.name,
                  !existingNames.contains(assetName) else { continue }
            imported.append(try importDocument(from: file))
        }
        return imported
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// Internal alias so this file doesn't need to know about the private
    /// debounce machinery in AssetStore.swift.
    fileprivate func saveDebounced() {
        // AssetStore's scheduleAutosave is private; mirror its effect via saveNow()
        // on the same debounce path isn't accessible here, so just save directly —
        // import/export are already explicit, infrequent, user-triggered actions.
        try? saveNow()
    }
}
