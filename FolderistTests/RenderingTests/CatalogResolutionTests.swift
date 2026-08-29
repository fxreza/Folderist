import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

/// The shipping app copies the repo's `Assets/` tree into `AssetPacks/`, so a catalog lands at
/// `AssetPacks/icons/<catalog>/…` — one level deeper than the old lookup expected, and two
/// levels deeper for Phosphor (`icons/phosphor/regular`). These tests pin every shape.
@Suite("Catalog resolution", .serialized)
struct CatalogResolutionTests {

    /// Builds a throwaway tree that mirrors the shipping bundle's resource layout.
    private func makeBundleLikeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("FolderistCatalog-\(UUID().uuidString)")
        let packs = root.appendingPathComponent("AssetPacks")
        let layout = [
            "icons/lucide": ["camera"],
            "icons/phosphor/regular": ["camera"],
            // `camera` exists in both weights, so this also pins which one wins.
            "icons/phosphor/fill": ["camera", "camera-fill"],
            "symbols/heroicons": ["beaker"],
            "emoji": ["1f680"]
        ]
        for (dir, names) in layout {
            let url = packs.appendingPathComponent(dir)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            for name in names {
                let svg = """
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">\
                <rect x="2" y="2" width="20" height="20" fill="#000"/></svg>
                """
                try svg.write(to: url.appendingPathComponent("\(name).svg"),
                              atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    @Test("CatalogLookup searches the bare, icons/ and symbols/ levels")
    func candidateDirectories() throws {
        let root = URL(fileURLWithPath: "/tmp/example")
        let dirs = CatalogLookup.directories(roots: [root], catalog: "lucide").map(\.path)
        #expect(dirs.contains("/tmp/example/lucide"))
        #expect(dirs.contains("/tmp/example/icons/lucide"))
        #expect(dirs.contains("/tmp/example/symbols/lucide"))
        #expect(dirs.contains("/tmp/example"))
    }

    @Test("a simulated bundle layout resolves every catalog shape")
    func simulatedBundleLayout() throws {
        let root = try makeBundleLikeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        // `AssetPacks/icons/<catalog>` — the shape the app bundle actually ships.
        let resources = DirectoryRenderResources(baseURL: root, preferBundledEmoji: true)
        #expect(resources.symbolImage(catalog: "lucide", name: "camera") != nil,
                "AssetPacks/icons/lucide did not resolve")
        // `AssetPacks/icons/phosphor/<weight>` — one level deeper again.
        #expect(resources.symbolImage(catalog: "phosphor", name: "camera") != nil,
                "AssetPacks/icons/phosphor/regular did not resolve")
        #expect(resources.symbolImage(catalog: "phosphor", name: "camera-fill") != nil,
                "AssetPacks/icons/phosphor/fill did not resolve")
        // When a name exists in more than one weight, the outline weight wins.
        let regular = try #require(CatalogLookup.find(
            name: "camera",
            in: CatalogLookup.directories(roots: [root.appendingPathComponent("AssetPacks")],
                                          catalog: "phosphor")))
        #expect(regular.deletingLastPathComponent().lastPathComponent == "regular")
        // `AssetPacks/symbols/<catalog>`.
        #expect(resources.symbolImage(catalog: "heroicons", name: "beaker") != nil,
                "AssetPacks/symbols/heroicons did not resolve")
        // Bundled emoji artwork.
        #expect(resources.emojiImage(for: "🚀") != nil, "AssetPacks/emoji did not resolve")
        // And a name that really is missing still returns nil rather than something random.
        #expect(resources.symbolImage(catalog: "lucide", name: "no-such-icon-name") == nil)
    }

    @Test("the same layout resolves through a real Bundle")
    func bundleProvider() throws {
        let fm = FileManager.default
        let bundleURL = fm.temporaryDirectory
            .appendingPathComponent("FolderistCatalog-\(UUID().uuidString).bundle")
        let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: bundleURL) }

        let info: [String: Any] = ["CFBundleIdentifier": "com.folderist.test.catalog",
                                   "CFBundlePackageType": "BNDL"]
        try (info as NSDictionary).write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        for dir in ["AssetPacks/icons/lucide", "AssetPacks/icons/phosphor/regular"] {
            let url = resourcesDir.appendingPathComponent(dir)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">\
            <rect x="2" y="2" width="20" height="20" fill="#000"/></svg>
            """
            try svg.write(to: url.appendingPathComponent("camera.svg"), atomically: true, encoding: .utf8)
        }

        let bundle = try #require(Bundle(url: bundleURL))
        let resources = BundleRenderResources(bundle: bundle)
        #expect(resources.catalogRoots.first?.lastPathComponent == "AssetPacks")
        #expect(resources.symbolImage(catalog: "lucide", name: "camera") != nil,
                "the bundle provider missed AssetPacks/icons/lucide")
        #expect(resources.symbolImage(catalog: "phosphor", name: "camera") != nil,
                "the bundle provider missed AssetPacks/icons/phosphor/regular")
    }

    @Test("the repo's own Assets tree resolves the catalogs the app ships")
    func repositoryAssets() throws {
        guard let assets = RenderFixtures.assetsDirectory else { return }
        let resources = DirectoryRenderResources(baseURL: assets)
        #expect(resources.symbolImage(catalog: "lucide", name: "camera") != nil)
        #expect(resources.symbolImage(catalog: "phosphor", name: "camera") != nil)
        // The `symbols/` catalogs live one level over from `icons/`.
        let symbols = assets.appendingPathComponent("symbols")
        if let packs = try? FileManager.default.contentsOfDirectory(atPath: symbols.path) {
            for pack in packs.prefix(2) where !pack.hasPrefix(".") {
                let dir = symbols.appendingPathComponent(pack)
                guard let first = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
                    .first(where: { $0.hasSuffix(".svg") }) else { continue }
                let name = (first as NSString).deletingPathExtension
                #expect(resources.symbolImage(catalog: pack, name: name) != nil,
                        "symbols/\(pack)/\(name) did not resolve")
            }
        }
    }

    @Test("a directory provider pointed straight at an unpacked AssetPacks tree also works")
    func assetPacksAsBase() throws {
        let root = try makeBundleLikeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = DirectoryRenderResources(baseURL: root.appendingPathComponent("AssetPacks"))
        #expect(resources.symbolImage(catalog: "lucide", name: "camera") != nil)
        #expect(resources.symbolImage(catalog: "phosphor", name: "camera") != nil)
    }
}
