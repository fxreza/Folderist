import XCTest
@testable import Folderist

final class CatalogIndexTests: XCTestCase {

    /// Points at the repo's real `Assets/` directory (Assets/emoji,
    /// Assets/icons/lucide, Assets/icons/phosphor) rather than a bundle.
    private static let repoAssetsDirectory: URL = {
        URL(fileURLWithPath: "/Users/sam/Claude/Code/Folderist/Assets")
    }()

    func testFindsSmileEmoji() {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        XCTAssertFalse(index.emoji.isEmpty, "expected emoji catalog to load from \(Self.repoAssetsDirectory.path)")
        let results = index.searchEmoji("smile")
        XCTAssertFalse(results.isEmpty, "expected at least one emoji to match 'smile'")
    }

    func testFindsCameraInLucide() {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        XCTAssertFalse(index.lucideIcons.isEmpty, "expected lucide catalog to load from \(Self.repoAssetsDirectory.path)")
        let results = index.searchIcons(catalog: "lucide", query: "camera")
        XCTAssertFalse(results.isEmpty, "expected at least one lucide icon to match 'camera'")
        XCTAssertTrue(results.contains { $0.name == "camera" })
    }

    func testFindsIconsInPhosphorRecursively() {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        XCTAssertFalse(index.phosphorIcons.isEmpty, "expected phosphor catalog to load recursively (fill/regular subfolders)")
        let results = index.searchIcons(catalog: "phosphor", query: "camera")
        XCTAssertFalse(results.isEmpty, "expected at least one phosphor icon to match 'camera'")
    }

    func testEmojiCharacterDecodesCorrectly() {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        let grinning = index.emoji.first { $0.codepoints == "1f600" }
        XCTAssertEqual(grinning?.character, "\u{1F600}")
    }

    /// The new monochrome sets under `Assets/symbols/*` and `Assets/textures/heropatterns`
    /// (#task: SHIP THE ASSETS / CATALOG INDEX) should index and resolve exactly like the
    /// pre-existing Lucide/Phosphor packs: loaded by `CatalogIndex`, and every entry's
    /// `(catalog, name)` pair resolvable through `DirectoryRenderResources` pointed at the
    /// repo's own `Assets/` tree.
    func testNewCatalogsLoadAndResolve() throws {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        let resources = DirectoryRenderResources(baseURL: Self.repoAssetsDirectory)

        let pools: [(catalog: String, entries: [CatalogIndex.IconEntry])] = [
            ("material", index.materialIcons),
            ("remix", index.remixIcons),
            ("bootstrap", index.bootstrapIcons),
            ("heroicons", index.heroiconsIcons),
            ("heropatterns", index.heropatternsTextures),
        ]
        for (catalog, entries) in pools {
            XCTAssertFalse(entries.isEmpty, "expected \(catalog) catalog to load from \(Self.repoAssetsDirectory.path)")
            let first = try XCTUnwrap(entries.first, "no entries loaded for \(catalog)")
            XCTAssertEqual(first.catalog, catalog)
            let image = resources.symbolImage(catalog: catalog, name: first.name)
            XCTAssertNotNil(image, "\(catalog)/\(first.name) did not resolve through DirectoryRenderResources")
        }
    }

    /// Remix and Bootstrap ship only the "-fill" weight baked into every filename; that suffix
    /// should disappear from `displayName` (used for search/tooltips) while `name` — the field
    /// that round-trips through `GraphicOverlay.bundledSymbol` and must match the file on disk —
    /// stays untouched.
    func testFillSuffixStrippedFromDisplayNameOnly() throws {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        for catalog in [index.remixIcons, index.bootstrapIcons] {
            let entry = try XCTUnwrap(catalog.first { $0.name.hasSuffix("-fill") })
            XCTAssertFalse(entry.displayName.hasSuffix("-fill"),
                           "expected '-fill' stripped from displayName, got \(entry.displayName)")
            XCTAssertTrue(entry.name.hasSuffix("-fill"), "the on-disk name must be left untouched")
        }
    }

    func testSearchIconsFindsMaterialAndHeroiconsByToken() {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        XCTAssertFalse(index.searchIcons(catalog: "material", query: "camera").isEmpty,
                       "expected at least one Material icon to match 'camera'")
        XCTAssertFalse(index.searchIcons(catalog: "heroicons", query: "camera").isEmpty,
                       "expected at least one Heroicons icon to match 'camera'")
    }

    func testSearchTexturesFindsHeropatterns() {
        let index = CatalogIndex(directoryOverride: Self.repoAssetsDirectory)
        XCTAssertFalse(index.searchTextures(query: "").isEmpty,
                       "expected the heropatterns catalog to be non-empty")
    }
}
