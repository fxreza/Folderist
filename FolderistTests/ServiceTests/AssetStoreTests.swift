import XCTest
@testable import Folderist

final class AssetStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// The app shows one grid, so the library seeds exactly one unlocked
    /// asset holding every starter style (the rainbow of basic colors is
    /// merged into it, and there is no separate Emoji asset).
    func testSeedsSingleUnlockedAssetOnFirstRun() {
        let store = AssetStore(rootDirectory: tempDir)
        XCTAssertEqual(store.library.assets.count, 1)
        XCTAssertEqual(store.library.assets[0].name, "Main Asset")
        XCTAssertFalse(store.library.assets[0].isLocked)
        XCTAssertGreaterThanOrEqual(store.library.assets[0].styles.count, 12)
        XCTAssertEqual(store.library.selectedAssetID, store.library.assets[0].id)
    }

    func testAddRenameDeleteAsset() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let asset = store.addAsset(name: "Work")
        XCTAssertTrue(store.library.assets.contains { $0.id == asset.id })

        try store.renameAsset(asset.id, to: "Projects")
        XCTAssertEqual(store.library.assets.first { $0.id == asset.id }?.name, "Projects")

        try store.deleteAsset(asset.id)
        XCTAssertFalse(store.library.assets.contains { $0.id == asset.id })
    }

    /// Nothing is seeded locked any more, but the guard itself still has to
    /// work for assets that are marked locked explicitly.
    func testCannotDeleteLockedAsset() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let asset = store.addAsset(name: "Locked")
        store.mutateLibrary { library in
            library.assets[library.assets.count - 1].isLocked = true
        }
        XCTAssertThrowsError(try store.deleteAsset(asset.id)) { error in
            XCTAssertEqual(error as? AssetStore.StoreError, .assetLocked)
        }
    }

    func testStyleCRUDAndMaxStylesEnforced() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let asset = store.addAsset(name: "Fill Test")

        for i in 0..<Asset.maxStyles {
            _ = try store.addStyle(Style(name: "S\(i)"), to: asset.id)
        }
        XCTAssertEqual(store.library.assets.first { $0.id == asset.id }?.styles.count, Asset.maxStyles)

        XCTAssertThrowsError(try store.addStyle(Style(name: "overflow"), to: asset.id)) { error in
            XCTAssertEqual(error as? AssetStore.StoreError, .styleLimitReached)
        }

        let firstStyleID = store.library.assets.first { $0.id == asset.id }!.styles[0].id
        try store.renameStyle(firstStyleID, in: asset.id, to: "Renamed")
        XCTAssertEqual(store.library.assets.first { $0.id == asset.id }?.styles[0].name, "Renamed")

        try store.deleteStyle(firstStyleID, from: asset.id)
        XCTAssertEqual(store.library.assets.first { $0.id == asset.id }?.styles.count, Asset.maxStyles - 1)
    }

    func testDuplicateAndCopyStyle() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let assetA = store.addAsset(name: "A")
        let assetB = store.addAsset(name: "B")
        let style = try store.addStyle(Style(name: "Original", fill: .solid(.folderBlue)), to: assetA.id)

        let duplicate = try store.duplicateStyle(style.id, in: assetA.id)
        XCTAssertNotEqual(duplicate.id, style.id)
        XCTAssertEqual(store.library.assets.first { $0.id == assetA.id }?.styles.count, 2)

        let copied = try store.copyStyle(style.id, from: assetA.id, to: assetB.id)
        XCTAssertNotEqual(copied.id, style.id)
        XCTAssertEqual(store.library.assets.first { $0.id == assetB.id }?.styles.count, 1)
    }

    func testReorderStylesAndAssets() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let asset = store.addAsset(name: "Reorderable")
        for name in ["A", "B", "C", "D"] {
            _ = try store.addStyle(Style(name: name), to: asset.id)
        }
        try store.reorderStyles(in: asset.id, from: IndexSet(integer: 0), to: 3)
        let names = store.library.assets.first { $0.id == asset.id }!.styles.map(\.name)
        XCTAssertEqual(names, ["B", "C", "A", "D"])

        let before = store.library.assets.map(\.name)
        store.reorderAssets(from: IndexSet(integer: 0), to: store.library.assets.count)
        let after = store.library.assets.map(\.name)
        XCTAssertEqual(after.last, before.first)
    }

    func testPersistenceRoundTrip() throws {
        let store1 = AssetStore(rootDirectory: tempDir)
        let asset = store1.addAsset(name: "Persisted")
        _ = try store1.addStyle(Style(name: "PersistedStyle", fill: .solid(StyleColor(red: 0.1, green: 0.2, blue: 0.3))), to: asset.id)
        try store1.saveNow()

        let store2 = AssetStore(rootDirectory: tempDir)
        XCTAssertTrue(store2.library.assets.contains { $0.name == "Persisted" })
        let reloadedAsset = store2.library.assets.first { $0.name == "Persisted" }!
        XCTAssertEqual(reloadedAsset.styles.first?.name, "PersistedStyle")
    }

    func testImportImageDedupesByHash() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let sourceFile = tempDir.appendingPathComponent("source.png")
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try data.write(to: sourceFile)

        let name1 = try store.importImage(from: sourceFile)
        let name2 = try store.importImage(from: sourceFile)
        XCTAssertEqual(name1, name2)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: name1)), data)
    }

    func testExportImportAssetRoundTripWithImage() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let sourceFile = tempDir.appendingPathComponent("icon.png")
        let imageBytes = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        try imageBytes.write(to: sourceFile)
        let fileName = try store.importImage(from: sourceFile)

        let asset = store.addAsset(name: "ExportMe")
        _ = try store.addStyle(
            Style(name: "WithImage", graphic: .image(fileName: fileName, mode: .over)),
            to: asset.id
        )

        let exportURL = tempDir.appendingPathComponent("export.folderist")
        try store.exportAsset(asset.id, to: exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        let imported = try store.importDocument(from: exportURL)
        XCTAssertNotEqual(imported.id, asset.id)
        XCTAssertEqual(imported.name, "ExportMe")
        XCTAssertEqual(imported.styles.count, 1)

        guard case .image(let importedFileName, let mode)? = imported.styles[0].graphic else {
            return XCTFail("expected image graphic overlay")
        }
        XCTAssertEqual(mode, .over)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: importedFileName)), imageBytes)
    }

    func testExportImportSingleStyle() throws {
        let store = AssetStore(rootDirectory: tempDir)
        let asset = store.addAsset(name: "StyleHolder")
        let style = try store.addStyle(Style(name: "Solo", fill: .solid(.folderBlue)), to: asset.id)

        let exportURL = tempDir.appendingPathComponent("style.folderist")
        try store.exportStyle(style.id, in: asset.id, to: exportURL)

        let imported = try store.importDocument(from: exportURL)
        XCTAssertEqual(imported.name, "Imported")
        XCTAssertEqual(imported.styles.first?.name, "Solo")
        XCTAssertNotEqual(imported.styles.first?.id, style.id)
    }

    func testSyncDirectoryExportImport() throws {
        let syncDir = tempDir.appendingPathComponent("iCloudSim")
        let store1 = AssetStore(rootDirectory: tempDir.appendingPathComponent("mac1"))
        store1.syncDirectoryOverride = syncDir
        let asset = store1.addAsset(name: "Synced")
        _ = try store1.addStyle(Style(name: "S"), to: asset.id)
        _ = try store1.exportAssetToSyncDirectory(asset.id)

        let store2 = AssetStore(rootDirectory: tempDir.appendingPathComponent("mac2"))
        store2.syncDirectoryOverride = syncDir
        let imported = try store2.importAllFromSyncDirectory()
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.name, "Synced")
    }
}
