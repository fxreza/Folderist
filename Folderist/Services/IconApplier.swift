import AppKit

/// Applies (or clears) a custom folder icon via `NSWorkspace`.
///
/// If a URL is a Finder alias or symlink, the icon is set both on the
/// resolved target (so the real folder shows the new icon everywhere) and
/// on the alias file itself (so the alias's own Finder entry updates too —
/// this is the behavior FolderMarker famously broke on Big Sur).
enum IconApplier {

    struct Result {
        let url: URL
        let success: Bool
    }

    /// Resolves `url` to the file/folder it ultimately refers to: follows
    /// Finder aliases (`.isAliasFile`) and symlinks. Returns `url` itself if
    /// it is not an alias/symlink or resolution fails.
    static func resolveTarget(_ url: URL) -> URL {
        if let values = try? url.resourceValues(forKeys: [.isAliasFileKey]), values.isAliasFile == true,
           let resolved = try? URL(resolvingAliasFileAt: url) {
            return resolved
        }
        let resolvedSymlink = url.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: resolvedSymlink.path) {
            return resolvedSymlink
        }
        return url
    }

    /// Applies `image` as the custom icon for `url`. If `url` is an alias,
    /// applies it to both the resolved target and the alias file itself.
    @discardableResult
    static func apply(image: NSImage, to url: URL) -> Bool {
        let target = resolveTarget(url)
        let targetOK = NSWorkspace.shared.setIcon(image, forFile: target.path, options: [])
        if target.path != url.path {
            _ = NSWorkspace.shared.setIcon(image, forFile: url.path, options: [])
        }
        return targetOK
    }

    /// Batch apply, one result per input URL (order preserved).
    static func apply(urls: [URL], image: NSImage) -> [Result] {
        urls.map { Result(url: $0, success: apply(image: image, to: $0)) }
    }

    /// Clears any custom icon, reverting to the system default for the item's type.
    @discardableResult
    static func restoreDefault(url: URL) -> Bool {
        let target = resolveTarget(url)
        let targetOK = NSWorkspace.shared.setIcon(nil, forFile: target.path, options: [])
        if target.path != url.path {
            _ = NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
        }
        return targetOK
    }
}
