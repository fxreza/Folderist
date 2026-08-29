import Foundation

/// Indexes the bundled asset packs (emoji + icon/texture libraries) for the
/// symbol/emoji pickers' search fields.
///
/// Layout expected under either the app bundle's `AssetPacks/` resource
/// directory or a `directoryOverride` (used by tests, pointed at the repo's
/// `Assets/` folder):
///   - `emoji/*.svg` (Twemoji; filenames are hyphen-joined codepoints, e.g. `1f600.svg`)
///   - `icons/lucide/*.svg`
///   - `icons/phosphor/**/*.svg` (nested `regular/`, `fill/`, etc. subdirectories)
///   - `symbols/material/*.svg`, `symbols/remix/*-fill.svg`, `symbols/bootstrap/*-fill.svg`,
///     `symbols/heroicons/*.svg`
///   - `textures/heropatterns/*.svg`
final class CatalogIndex {

    struct EmojiEntry: Equatable {
        let character: String
        let codepoints: String   // e.g. "1f600" or "1f1e6-1f1e8"
        let name: String         // best-effort Unicode name of the primary scalar
        let keywords: [String]
    }

    struct IconEntry: Equatable {
        let catalog: String      // "lucide", "phosphor", "material", "remix", "bootstrap", "heroicons", "heropatterns"
        let name: String         // file stem, exactly as on disk, e.g. "camera" or "camera-fill" — this is
                                  // what round-trips through `GraphicOverlay.bundledSymbol(catalog:name:)`
        let displayName: String  // `name` with known style suffixes ("-fill", "-solid") stripped, for
                                  // search and tooltips
        let url: URL
    }

    /// When set, assets are read from this directory instead of the app bundle
    /// (e.g. the repo's `Assets/` directory in tests).
    let directoryOverride: URL?

    private(set) var emoji: [EmojiEntry] = []
    private(set) var lucideIcons: [IconEntry] = []
    private(set) var phosphorIcons: [IconEntry] = []
    private(set) var materialIcons: [IconEntry] = []
    private(set) var remixIcons: [IconEntry] = []
    private(set) var bootstrapIcons: [IconEntry] = []
    private(set) var heroiconsIcons: [IconEntry] = []
    private(set) var heropatternsTextures: [IconEntry] = []

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        reload()
    }

    func reload() {
        emoji = CatalogIndex.loadEmoji(from: emojiDirectory())
        lucideIcons = CatalogIndex.loadIcons(catalog: "lucide", from: iconsDirectory("lucide"))
        phosphorIcons = CatalogIndex.loadIcons(catalog: "phosphor", from: iconsDirectory("phosphor"))
        materialIcons = CatalogIndex.loadIcons(catalog: "material", from: symbolsDirectory("material"))
        remixIcons = CatalogIndex.loadIcons(catalog: "remix", from: symbolsDirectory("remix"))
        bootstrapIcons = CatalogIndex.loadIcons(catalog: "bootstrap", from: symbolsDirectory("bootstrap"))
        heroiconsIcons = CatalogIndex.loadIcons(catalog: "heroicons", from: symbolsDirectory("heroicons"))
        heropatternsTextures = CatalogIndex.loadIcons(catalog: "heropatterns", from: texturesDirectory("heropatterns"))
    }

    // MARK: Directory resolution

    private func emojiDirectory() -> URL? {
        if let override = directoryOverride { return override.appendingPathComponent("emoji") }
        return Bundle.main.url(forResource: "emoji", withExtension: nil, subdirectory: "AssetPacks")
    }

    private func iconsDirectory(_ pack: String) -> URL? {
        if let override = directoryOverride { return override.appendingPathComponent("icons/\(pack)") }
        return Bundle.main.url(forResource: pack, withExtension: nil, subdirectory: "AssetPacks/icons")
    }

    private func symbolsDirectory(_ pack: String) -> URL? {
        if let override = directoryOverride { return override.appendingPathComponent("symbols/\(pack)") }
        return Bundle.main.url(forResource: pack, withExtension: nil, subdirectory: "AssetPacks/symbols")
    }

    private func texturesDirectory(_ pack: String) -> URL? {
        if let override = directoryOverride { return override.appendingPathComponent("textures/\(pack)") }
        return Bundle.main.url(forResource: pack, withExtension: nil, subdirectory: "AssetPacks/textures")
    }

    // MARK: Search

    func searchEmoji(_ query: String) -> [EmojiEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return emoji }
        return emoji.filter { entry in
            entry.name.lowercased().contains(q) || entry.keywords.contains { $0.contains(q) }
        }
    }

    func searchIcons(catalog: String? = nil, query: String) -> [IconEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pool: [IconEntry]
        switch catalog {
        case "lucide": pool = lucideIcons
        case "phosphor": pool = phosphorIcons
        case "material": pool = materialIcons
        case "remix": pool = remixIcons
        case "bootstrap": pool = bootstrapIcons
        case "heroicons": pool = heroiconsIcons
        case "heropatterns": pool = heropatternsTextures
        default: pool = lucideIcons + phosphorIcons + materialIcons + remixIcons + bootstrapIcons + heroiconsIcons
        }
        guard !q.isEmpty else { return pool }
        return pool.filter { entry in
            let hay = entry.displayName.lowercased()
            return hay.split(whereSeparator: { $0 == "-" || $0 == "_" }).contains { $0.contains(q) }
                || hay.contains(q)
        }
    }

    /// Searches the bundled seamless-pattern textures (currently just `heropatterns`).
    func searchTextures(query: String) -> [IconEntry] {
        searchIcons(catalog: "heropatterns", query: query)
    }

    /// Searches every bundled icon catalog plus the textures, textures last —
    /// backs the symbol picker's combined "All Symbols" source (SF Symbols
    /// are searched separately, from `SFSymbolCatalog`, since they aren't
    /// part of this index).
    func searchAllIcons(query: String) -> [IconEntry] {
        searchIcons(query: query) + searchTextures(query: query)
    }

    // MARK: Loading

    private static func loadEmoji(from directory: URL?) -> [EmojiEntry] {
        guard let directory else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "svg" }
            .compactMap { entry(forEmojiFile: $0) }
            .sorted { $0.codepoints < $1.codepoints }
    }

    private static func entry(forEmojiFile url: URL) -> EmojiEntry? {
        let stem = url.deletingPathExtension().lastPathComponent
        let hexParts = stem.split(separator: "-").map(String.init)
        var scalars: [Unicode.Scalar] = []
        for hex in hexParts {
            guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else { continue }
            scalars.append(scalar)
        }
        guard !scalars.isEmpty else { return nil }
        let character = String(String.UnicodeScalarView(scalars))

        // Prefer the name of the first "real" (non-joiner/variation-selector) scalar.
        let namedScalar = scalars.first { $0.properties.generalCategory != .format } ?? scalars[0]
        let unicodeName = namedScalar.properties.name?.lowercased() ?? ""

        var keywords = Set(unicodeName.split(separator: " ").map(String.init))
        keywords.insert(unicodeName)
        for extra in keywordOverrides[stem] ?? [] {
            keywords.insert(extra)
        }

        return EmojiEntry(character: character, codepoints: stem, name: unicodeName, keywords: Array(keywords))
    }

    /// Small hand-picked alias map for common search terms whose everyday
    /// word doesn't literally appear inside the formal Unicode character
    /// name (e.g. "smile" vs. the name "SMILING FACE ..."). Keyed by the
    /// emoji's codepoint filename stem.
    private static let keywordOverrides: [String: [String]] = [
        "1f600": ["smile", "happy", "grin"],
        "1f601": ["smile", "happy", "grin"],
        "1f602": ["smile", "happy", "laugh", "lol"],
        "1f603": ["smile", "happy"],
        "1f604": ["smile", "happy"],
        "1f605": ["smile", "happy", "sweat"],
        "1f606": ["smile", "happy", "laugh"],
        "1f60a": ["smile", "happy", "blush"],
        "1f642": ["smile", "happy"],
        "263a": ["smile", "happy"],
        "2764": ["heart", "love"],
        "1f525": ["fire", "hot", "lit"],
        "2b50": ["star"],
        "1f44d": ["thumbs up", "like", "good"],
        "1f680": ["rocket", "launch"],
    ]

    private static func loadIcons(catalog: String, from directory: URL?) -> [IconEntry] {
        guard let directory else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [IconEntry] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "svg" {
            let name = url.deletingPathExtension().lastPathComponent
            results.append(IconEntry(catalog: catalog, name: name,
                                      displayName: displayName(forFileStem: name), url: url))
        }
        return results.sorted { $0.name < $1.name }
    }

    /// Style suffixes some packs bake into every filename (Remix, Bootstrap ship only the
    /// "-fill" weight; some Material icons carry "-outline"/"-round" variants). Stripped for
    /// search and tooltips so e.g. "camera-fill" is still found by searching "camera".
    private static let knownFileSuffixes = ["-fill", "-solid", "-outline", "-round", "-sharp"]

    private static func displayName(forFileStem stem: String) -> String {
        for suffix in knownFileSuffixes where stem.hasSuffix(suffix) {
            return String(stem.dropLast(suffix.count))
        }
        return stem
    }
}
