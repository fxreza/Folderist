import XCTest
@testable import Folderist

final class TagServiceTests: XCTestCase {

    func testNearestTagForPrimaryColors() {
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 0.95, green: 0.30, blue: 0.30)), .red)
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 1.0, green: 0.60, blue: 0.0)), .orange)
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 0.99, green: 0.80, blue: 0.20)), .yellow)
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 0.30, green: 0.69, blue: 0.31)), .green)
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 0.26, green: 0.52, blue: 0.96)), .blue)
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 0.61, green: 0.35, blue: 0.71)), .purple)
        XCTAssertEqual(TagService.nearestTag(to: StyleColor(red: 0.60, green: 0.60, blue: 0.60)), .gray)
    }

    func testNearestTagNeverReturnsNone() {
        for _ in 0..<20 {
            let color = StyleColor(red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1))
            XCTAssertNotEqual(TagService.nearestTag(to: color), .none)
        }
    }

    func testSetTagOnRealFileRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let folder = tempDir.appendingPathComponent("Tagged")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try TagService.setTag(.blue, on: folder)
        let values = try (folder as NSURL).resourceValues(forKeys: [.tagNamesKey])
        let names = values[.tagNamesKey] as? [String] ?? []
        XCTAssertTrue(names.contains("Blue"))

        try TagService.setTag(.none, on: folder)
        let clearedValues = try (folder as NSURL).resourceValues(forKeys: [.tagNamesKey])
        let clearedNames = clearedValues[.tagNamesKey] as? [String] ?? []
        XCTAssertFalse(clearedNames.contains("Blue"))
    }

    func testApplyTagIfRequestedRespectsFlag() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let folder = tempDir.appendingPathComponent("Untagged")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var style = Style(name: "NoTag", fill: .solid(StyleColor(red: 0.95, green: 0.30, blue: 0.30)))
        style.applyColorTag = false
        try TagService.applyTagIfRequested(for: style, to: folder)
        let values = try (folder as NSURL).resourceValues(forKeys: [.tagNamesKey])
        XCTAssertTrue((values[.tagNamesKey] as? [String] ?? []).isEmpty)

        style.applyColorTag = true
        try TagService.applyTagIfRequested(for: style, to: folder)
        let tagged = try (folder as NSURL).resourceValues(forKeys: [.tagNamesKey])
        XCTAssertTrue((tagged[.tagNamesKey] as? [String] ?? []).contains("Red"))
    }
}
