import XCTest
import AppKit
@testable import Folderist

final class SmartRestoreStoreTests: XCTestCase {

    private var tempDir: URL!
    private var storeRoot: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storeRoot = tempDir.appendingPathComponent("store")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFolder(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTestImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return image
    }

    func testNoSnapshotWhenNoCustomIcon() {
        let folder = makeFolder(named: "Plain")
        let restoreStore = SmartRestoreStore(rootDirectory: storeRoot)
        XCTAssertFalse(restoreStore.hasCustomIcon(at: folder))
        XCTAssertFalse(restoreStore.snapshotIfNeeded(for: folder))
    }

    func testSnapshotAndRestoreRoundTrip() {
        let folder = makeFolder(named: "Custom")
        let restoreStore = SmartRestoreStore(rootDirectory: storeRoot)

        // Give the folder a "pre-existing" custom icon.
        _ = IconApplier.apply(image: makeTestImage(color: .systemRed), to: folder)
        XCTAssertTrue(restoreStore.hasCustomIcon(at: folder))

        XCTAssertTrue(restoreStore.snapshotIfNeeded(for: folder))
        XCTAssertTrue(restoreStore.hasSnapshot(for: folder))

        // Overwrite with a new icon, simulating a Folderist style apply.
        _ = IconApplier.apply(image: makeTestImage(color: .systemGreen), to: folder)

        let restored = restoreStore.restore(url: folder)
        XCTAssertTrue(restored)
        XCTAssertFalse(restoreStore.hasSnapshot(for: folder), "snapshot should be consumed after restore")
    }

    func testRestoreWithoutSnapshotClearsToDefault() {
        let folder = makeFolder(named: "NoSnapshot")
        let restoreStore = SmartRestoreStore(rootDirectory: storeRoot)
        XCTAssertFalse(restoreStore.hasSnapshot(for: folder))
        let restored = restoreStore.restore(url: folder)
        XCTAssertTrue(restored)
    }

    func testIndexSurvivesReload() {
        let folder = makeFolder(named: "Reloaded")
        let store1 = SmartRestoreStore(rootDirectory: storeRoot)
        _ = IconApplier.apply(image: makeTestImage(color: .systemPurple), to: folder)
        XCTAssertTrue(store1.snapshotIfNeeded(for: folder))

        let store2 = SmartRestoreStore(rootDirectory: storeRoot)
        XCTAssertTrue(store2.hasSnapshot(for: folder))
    }
}
