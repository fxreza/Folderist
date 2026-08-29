import AppKit
import Foundation

/// Everything the renderer needs from the outside world: bundled glyph catalogs,
/// user-imported images, and (optionally) bundled emoji artwork.
///
/// The renderer itself never touches the filesystem, which keeps it pure and testable.
protocol RenderResources {
    /// Resolves `GraphicOverlay.bundledSymbol(catalog:name:)` to an image.
    /// SVG is loaded natively by `NSImage(contentsOf:)` on macOS 11+.
    func symbolImage(catalog: String, name: String) -> NSImage?

    /// Resolves `GraphicOverlay.image(fileName:mode:)` — a file stored in the style's asset folder.
    func userImage(named fileName: String) -> NSImage?

    /// Optional bundled artwork for an emoji cluster (e.g. Twemoji SVGs).
    /// Returning `nil` (the default) makes the renderer fall back to the system emoji font.
    func emojiImage(for emoji: String) -> NSImage?

    /// The user-supplied base folder bitmap, when one is installed.
    ///
    /// Returning `nil` (the default) makes the renderer draw its vector folder instead, so a
    /// provider that knows nothing about base artwork keeps working unchanged.
    var baseFolderArt: BaseFolderArt? { get }
}

extension RenderResources {
    func emojiImage(for emoji: String) -> NSImage? { nil }
    var baseFolderArt: BaseFolderArt? { nil }
}

// MARK: - Shared cache

/// Small thread-safe image cache shared by the concrete resource providers.
final class RenderResourceCache {
    static let shared = RenderResourceCache()
    private let lock = NSLock()
    private var storage: [String: NSImage] = [:]

    func image(for key: String, make: () -> NSImage?) -> NSImage? {
        lock.lock()
        if let hit = storage[key] { lock.unlock(); return hit }
        lock.unlock()
        let made = make()
        if let made {
            lock.lock()
            storage[key] = made
            lock.unlock()
        }
        return made
    }

    func removeAll() {
        lock.lock(); storage.removeAll(); lock.unlock()
    }
}

// MARK: - File lookup

enum ResourceFile {
    /// Extensions we try, in order, when resolving a catalog symbol or user image.
    static let imageExtensions = ["svg", "pdf", "png", "jpg", "jpeg", "tiff", "heic", "gif", "webp", "icns"]

    static func firstExisting(in directory: URL, baseName: String) -> URL? {
        let fm = FileManager.default
        // An explicit extension wins.
        if !(baseName as NSString).pathExtension.isEmpty {
            let direct = directory.appendingPathComponent(baseName)
            if fm.fileExists(atPath: direct.path) { return direct }
        }
        for ext in imageExtensions {
            let url = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

// MARK: - Catalog lookup

/// Shared resolution rules for glyph catalogs, so the bundle-backed and directory-backed
/// providers can never drift apart.
///
/// Catalogs live at different depths depending on where they came from: the repo's `Assets/`
/// tree puts them under `icons/`, `symbols/`, or `textures/`, and the shipping app copies that
/// tree wholesale into `AssetPacks/`, so the same catalog is at `AssetPacks/icons/<catalog>` (or
/// `symbols/`, `textures/`). Phosphor adds one more level (`phosphor/regular`, `phosphor/fill`),
/// which the child-directory sweep below covers.
enum CatalogLookup {
    /// Intermediate directories a catalog may sit under, relative to a resource root.
    static let intermediates = ["", "icons", "symbols", "textures"]

    /// Every directory that could hold `catalog`, most specific first.
    static func directories(roots: [URL], catalog: String) -> [URL] {
        var out: [URL] = []
        for root in roots {
            for middle in intermediates {
                var dir = root
                if !middle.isEmpty { dir.appendPathComponent(middle) }
                if !catalog.isEmpty { dir.appendPathComponent(catalog) }
                out.append(dir)
            }
            out.append(root)
        }
        return out
    }

    /// Weight/style subdirectories worth trying before the rest, so `phosphor/camera` resolves
    /// to the outline weight rather than to whichever directory the filesystem listed first.
    static let preferredWeights = ["regular", "outline", "line", "default", "normal"]

    /// Finds `name` in `directories`, also looking one level into each directory's own
    /// subdirectories (weight/style splits such as `phosphor/regular` and `phosphor/fill`).
    static func find(name: String, in directories: [URL]) -> URL? {
        let fm = FileManager.default
        for dir in directories {
            if let url = ResourceFile.firstExisting(in: dir, baseName: name) { return url }
            guard let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { continue }
            let subdirectories = children
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .sorted { a, b in
                    let ra = preferredWeights.firstIndex(of: a.lastPathComponent.lowercased()) ?? .max
                    let rb = preferredWeights.firstIndex(of: b.lastPathComponent.lowercased()) ?? .max
                    return ra == rb ? a.lastPathComponent < b.lastPathComponent : ra < rb
                }
            for child in subdirectories {
                if let url = ResourceFile.firstExisting(in: child, baseName: name) { return url }
            }
        }
        return nil
    }
}

// MARK: - Bundle-backed resources (shipping app)

/// Looks glyph catalogs up inside the app bundle's `AssetPacks/` resource directory, and user
/// images in an explicit directory (the style's asset folder).
///
/// The shipping bundle mirrors the repo's `Assets/` tree, so the catalogs actually live at
/// `AssetPacks/icons/<catalog>/…` (and `AssetPacks/icons/phosphor/{regular,fill}/…`), not at
/// `AssetPacks/<catalog>/…`. `CatalogLookup` covers every one of those shapes.
struct BundleRenderResources: RenderResources {
    let bundle: Bundle
    let assetPacksSubdirectory: String
    let userImagesDirectory: URL?
    /// When true, `emoji(_:)` overlays use bundled artwork from the `emoji` pack instead of the system font.
    let preferBundledEmoji: Bool

    init(bundle: Bundle = .main,
         assetPacksSubdirectory: String = "AssetPacks",
         userImagesDirectory: URL? = nil,
         preferBundledEmoji: Bool = false) {
        self.bundle = bundle
        self.assetPacksSubdirectory = assetPacksSubdirectory
        self.userImagesDirectory = userImagesDirectory
        self.preferBundledEmoji = preferBundledEmoji
    }

    /// Resource roots searched for catalogs, most specific first.
    var catalogRoots: [URL] {
        guard let resources = bundle.resourceURL else { return [] }
        var roots: [URL] = []
        if !assetPacksSubdirectory.isEmpty {
            roots.append(resources.appendingPathComponent(assetPacksSubdirectory))
        }
        roots.append(resources)
        return roots
    }

    func symbolImage(catalog: String, name: String) -> NSImage? {
        let key = "bundle:\(bundle.bundlePath)|\(assetPacksSubdirectory)/\(catalog)/\(name)"
        return RenderResourceCache.shared.image(for: key) {
            if let url = CatalogLookup.find(
                name: name, in: CatalogLookup.directories(roots: catalogRoots, catalog: catalog)) {
                return NSImage(contentsOf: url)
            }
            // Bundles that flattened the resource tree: ask LaunchServices' own index.
            for sub in ["\(assetPacksSubdirectory)/icons/\(catalog)",
                        "\(assetPacksSubdirectory)/symbols/\(catalog)",
                        "\(assetPacksSubdirectory)/textures/\(catalog)",
                        "\(assetPacksSubdirectory)/\(catalog)"] {
                for ext in ResourceFile.imageExtensions {
                    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) {
                        return NSImage(contentsOf: url)
                    }
                }
            }
            for ext in ResourceFile.imageExtensions {
                if let url = bundle.url(forResource: name, withExtension: ext) {
                    return NSImage(contentsOf: url)
                }
            }
            return nil
        }
    }

    func userImage(named fileName: String) -> NSImage? {
        guard let dir = userImagesDirectory else { return nil }
        return DirectoryRenderResources.loadUserImage(named: fileName, in: dir)
    }

    func emojiImage(for emoji: String) -> NSImage? {
        guard preferBundledEmoji else { return nil }
        return symbolImage(catalog: "emoji", name: EmojiAssetNaming.fileBaseName(for: emoji))
    }

    /// The user's own `Contents/Resources/BaseFolder/BaseFolder.{icns,png}` — or the same file
    /// loose in `Contents/Resources/`, so a bundle that flattened the tree still finds it —
    /// falling back to the system folder icon read off the running Mac.
    var baseFolderArt: BaseFolderArt? {
        BaseFolderArt.shared(roots: [bundle.resourceURL].compactMap { $0 },
                             allowingSystemFallback: true)
    }
}

// MARK: - Directory-backed resources (tests, previews, dev builds)

/// Resolves catalogs from a directory tree such as the repo's `Assets/` folder:
/// `<base>/icons/<catalog>/<name>.svg`, `<base>/symbols/<catalog>/<name>.svg`,
/// `<base>/<catalog>/<name>.svg`, `<base>/AssetPacks/icons/<catalog>/<name>.svg`,
/// `<base>/<name>.svg`, plus one level of weight/style subdirectory (`phosphor/regular`).
struct DirectoryRenderResources: RenderResources {
    let baseURL: URL
    let userImagesDirectory: URL
    /// When true, `emoji(_:)` overlays use `<base>/emoji/<codepoints>.svg` (Twemoji naming).
    let preferBundledEmoji: Bool
    /// Where the base folder bitmap is looked for. Defaults to `<base>/BaseFolder/`, then
    /// `<base>/`; pass an explicit directory to point tests or previews at other artwork.
    let baseFolderDirectory: URL?
    /// Whether to fall back to the system folder icon when no artwork is on disk.
    ///
    /// `false` here (unlike the shipping bundle) so that tests, previews and the app-icon script
    /// render exactly what their directory holds and nothing that depends on the host Mac.
    let preferSystemBaseFolder: Bool

    init(baseURL: URL, userImagesDirectory: URL? = nil, preferBundledEmoji: Bool = false,
         baseFolderDirectory: URL? = nil, preferSystemBaseFolder: Bool = false) {
        self.baseURL = baseURL
        self.userImagesDirectory = userImagesDirectory ?? baseURL
        self.preferBundledEmoji = preferBundledEmoji
        self.baseFolderDirectory = baseFolderDirectory
        self.preferSystemBaseFolder = preferSystemBaseFolder
    }

    var baseFolderArt: BaseFolderArt? {
        BaseFolderArt.shared(roots: [baseFolderDirectory ?? baseURL],
                             allowingSystemFallback: preferSystemBaseFolder)
    }

    /// Resource roots searched for catalogs, most specific first. `AssetPacks` is included so a
    /// directory provider pointed at an unpacked bundle resolves exactly like the bundle one.
    var catalogRoots: [URL] {
        [baseURL, baseURL.appendingPathComponent("AssetPacks")]
    }

    func symbolImage(catalog: String, name: String) -> NSImage? {
        let key = "dir:\(baseURL.path)|\(catalog)/\(name)"
        return RenderResourceCache.shared.image(for: key) {
            CatalogLookup.find(name: name,
                               in: CatalogLookup.directories(roots: catalogRoots, catalog: catalog))
                .flatMap(NSImage.init(contentsOf:))
        }
    }

    func userImage(named fileName: String) -> NSImage? {
        Self.loadUserImage(named: fileName, in: userImagesDirectory)
    }

    func emojiImage(for emoji: String) -> NSImage? {
        guard preferBundledEmoji else { return nil }
        return symbolImage(catalog: "emoji", name: EmojiAssetNaming.fileBaseName(for: emoji))
    }

    static func loadUserImage(named fileName: String, in directory: URL) -> NSImage? {
        let key = "user:\(directory.path)|\(fileName)"
        return RenderResourceCache.shared.image(for: key) {
            // Absolute paths are accepted verbatim so callers can pass a full URL path.
            if fileName.hasPrefix("/"), FileManager.default.fileExists(atPath: fileName) {
                return NSImage(contentsOfFile: fileName)
            }
            let direct = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: direct.path) {
                return NSImage(contentsOf: direct)
            }
            return ResourceFile.firstExisting(in: directory, baseName: fileName).flatMap(NSImage.init(contentsOf:))
        }
    }
}

// MARK: - Emoji asset naming

enum EmojiAssetNaming {
    /// Twemoji-style file base name: hyphen-joined lowercase code points, variation selectors dropped.
    static func fileBaseName(for emoji: String) -> String {
        let points = emoji.unicodeScalars
            .filter { $0.value != 0xFE0F }
            .map { String($0.value, radix: 16) }
        return points.joined(separator: "-")
    }
}

/// Resource provider that resolves nothing — useful for previews and tests of the base folder.
struct EmptyRenderResources: RenderResources {
    init() {}
    func symbolImage(catalog: String, name: String) -> NSImage? { nil }
    func userImage(named fileName: String) -> NSImage? { nil }
}
