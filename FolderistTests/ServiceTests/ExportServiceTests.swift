import XCTest
import AppKit
@testable import Folderist

final class ExportServiceTests: XCTestCase {

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

    private func dummyImage(pixelSize: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
        image.unlockFocus()
        return image
    }

    private func allSizeImages() -> [Int: NSImage] {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        return Dictionary(uniqueKeysWithValues: sizes.map { ($0, dummyImage(pixelSize: $0)) })
    }

    func testWriteIconsetProducesExpectedFiles() throws {
        let iconsetDir = tempDir.appendingPathComponent("Test.iconset")
        try ExportService.writeIconset(images: allSizeImages(), to: iconsetDir)

        for entry in ExportService.iconsetEntries {
            let fileURL = iconsetDir.appendingPathComponent(entry.name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "missing \(entry.name)")
        }
    }

    func testWriteICNSSucceedsViaIconutil() throws {
        let icnsURL = tempDir.appendingPathComponent("Test.icns")
        try ExportService.writeICNS(images: allSizeImages(), to: icnsURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: icnsURL.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: icnsURL.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testWritePNGProducesValidImage() throws {
        let pngURL = tempDir.appendingPathComponent("Test.png")
        try ExportService.writePNG(image: dummyImage(pixelSize: 1024), pixelSize: 1024, to: pngURL)

        let data = try Data(contentsOf: pngURL)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "not a PNG signature")
        let rep = NSBitmapImageRep(data: data)
        XCTAssertEqual(rep?.pixelsWide, 1024)
        XCTAssertEqual(rep?.pixelsHigh, 1024)
    }

    func testWriteIconsetSkipsMissingSizes() throws {
        let iconsetDir = tempDir.appendingPathComponent("Partial.iconset")
        try ExportService.writeIconset(images: [1024: dummyImage(pixelSize: 1024)], to: iconsetDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconsetDir.appendingPathComponent("icon_512x512@2x.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: iconsetDir.appendingPathComponent("icon_16x16.png").path))
    }
}
