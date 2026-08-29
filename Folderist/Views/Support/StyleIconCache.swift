import AppKit

/// Caches `FolderIconRenderer` output for the main window's large grid tiles
/// and the editor preview.
///
/// Keyed by the `Style` value *and* the canvas size: `Style` is `Hashable`
/// over every field that affects its rendering, so an edited style simply
/// misses the cache and re-renders — there is no invalidation bookkeeping to
/// get wrong.
final class StyleIconCache {
    static let shared = StyleIconCache()

    /// Source resolution for grid tiles — drawn at ~110 pt, so 256 px keeps
    /// them crisp on Retina without paying 1024 px render cost per tile.
    static let gridCanvas: CGFloat = 256
    /// Source resolution for the editor's big live preview.
    static let previewCanvas: CGFloat = 512

    private struct Key: Hashable {
        let style: Style
        let canvas: Int
    }

    private var storage: [Key: NSImage] = [:]
    private var order: [Key] = []
    private let lock = NSLock()
    private let capacity = 240

    func icon(for style: Style, canvas: CGFloat, resources: RenderResources) -> NSImage {
        let key = Key(style: style, canvas: Int(canvas.rounded()))

        lock.lock()
        if let hit = storage[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let image = FolderIconRenderer.renderIcon(style: style, canvas: canvas, resources: resources)

        lock.lock()
        if order.count >= capacity {
            // Cheap FIFO eviction: drop the oldest quarter in one pass.
            let drop = order.prefix(capacity / 4)
            for k in drop { storage.removeValue(forKey: k) }
            order.removeFirst(drop.count)
        }
        storage[key] = image
        order.append(key)
        lock.unlock()
        return image
    }

    func gridIcon(for style: Style, resources: RenderResources) -> NSImage {
        icon(for: style, canvas: Self.gridCanvas, resources: resources)
    }

    func previewIcon(for style: Style, resources: RenderResources) -> NSImage {
        icon(for: style, canvas: Self.previewCanvas, resources: resources)
    }
}
