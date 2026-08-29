import XCTest
import AppKit
@testable import Folderist

final class IconApplierTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        image.unlockFocus()
        return image
    }

    func testApplyAndRestoreDefault() {
        let folder = makeFolder(named: "Target")
        let image = makeTestImage()

        let applied = IconApplier.apply(image: image, to: folder)
        XCTAssertTrue(applied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path))

        let restored = IconApplier.restoreDefault(url: folder)
        XCTAssertTrue(restored)
    }

    func testBatchApplyReturnsPerURLResults() {
        let folders = (0..<3).map { makeFolder(named: "Batch\($0)") }
        let image = makeTestImage()
        let results = IconApplier.apply(urls: folders, image: image)
        XCTAssertEqual(results.count, 3)
        for result in results {
            XCTAssertTrue(result.success)
        }
    }

    func testResolveTargetFollowsSymlink() throws {
        let realFolder = makeFolder(named: "Real")
        let symlinkURL = tempDir.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realFolder)

        let resolved = IconApplier.resolveTarget(symlinkURL)
        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, realFolder.resolvingSymlinksInPath().path)
    }
}
