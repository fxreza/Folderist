import AppKit
import SwiftUI

/// Loads and caches small glyph previews for bundled-catalog symbols
/// (Lucide/Phosphor SVGs indexed by `CatalogIndex`). `NSImage(contentsOf:)`
/// rasterizes SVG documents natively on macOS 11+, so no extra SVG
/// dependency is required.
enum PreviewGlyphLoader {
    private static let cache = NSCache<NSURL, NSImage>()

    /// Returns a cached, template-rendered NSImage for the glyph at `url`,
    /// loading and caching it on first access. `nil` if the file can't be
    /// decoded (e.g. missing asset pack in this build).
    static func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }

    /// Drops all cached previews. Exposed for callers that reload the
    /// catalog (e.g. after re-pointing `CatalogIndex.directoryOverride`).
    static func clearCache() {
        cache.removeAllObjects()
    }
}

/// Displays one bundled-catalog glyph (Lucide/Phosphor SVG) as a monochrome
/// template image, scaled to fit its cell. Falls back to a placeholder
/// glyph if the file can't be loaded.
struct PreviewGlyph: View {
    let url: URL

    var body: some View {
        Group {
            if let nsImage = PreviewGlyphLoader.image(for: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.4)
            }
        }
    }
}
