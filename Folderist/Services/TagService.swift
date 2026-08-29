import Foundation

/// The 7 Finder label colors plus "no tag".
enum FinderTagColor: String, CaseIterable, Equatable {
    case none, gray, green, purple, blue, yellow, red, orange

    /// Reference RGB used for nearest-color matching (macOS Finder's label swatches).
    var referenceColor: StyleColor? {
        switch self {
        case .none: return nil
        case .gray: return StyleColor(red: 0.596, green: 0.596, blue: 0.596)
        case .green: return StyleColor(red: 0.298, green: 0.686, blue: 0.314)
        case .purple: return StyleColor(red: 0.607, green: 0.349, blue: 0.713)
        case .blue: return StyleColor(red: 0.259, green: 0.522, blue: 0.957)
        case .yellow: return StyleColor(red: 0.988, green: 0.804, blue: 0.235)
        case .red: return StyleColor(red: 0.937, green: 0.325, blue: 0.314)
        case .orange: return StyleColor(red: 1.0, green: 0.596, blue: 0.0)
        }
    }

    /// The Finder tag name to write via `URLResourceValues.tagNames`
    /// (macOS's default tags are named exactly after their label colors).
    var finderTagName: String? {
        self == .none ? nil : rawValue.capitalized
    }
}

/// Maps `StyleColor`s to the nearest Finder tag color and applies/clears
/// that tag on files/folders via `URLResourceValues`.
enum TagService {

    /// Nearest of the 7 Finder label colors to `color` (never `.none`).
    static func nearestTag(to color: StyleColor) -> FinderTagColor {
        var best: FinderTagColor = .gray
        var bestDistance = Double.greatestFiniteMagnitude
        for tag in FinderTagColor.allCases {
            guard let reference = tag.referenceColor else { continue }
            let dr = color.red - reference.red
            let dg = color.green - reference.green
            let db = color.blue - reference.blue
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = tag
            }
        }
        return best
    }

    /// Sets (or clears, for `.none`) a single Finder tag on `url`, replacing
    /// any tags previously set by Folderist. Existing unrelated tags a user
    /// manually added are preserved.
    static func setTag(_ tag: FinderTagColor, on url: URL) throws {
        // `URLResourceValues.tagNames`'s setter requires a macOS 26 deployment
        // target; go through the older untyped NSURL API instead, which has
        // been available since 10.9 and reads/writes the same resource key.
        let nsURL = url as NSURL
        var existing = (try? nsURL.resourceValues(forKeys: [.tagNamesKey]))?[.tagNamesKey] as? [String] ?? []
        existing.removeAll { name in FinderTagColor.allCases.compactMap(\.finderTagName).contains(name) }
        if let name = tag.finderTagName {
            existing.append(name)
        }
        try nsURL.setResourceValue(existing, forKey: .tagNamesKey)
    }

    /// Convenience: derive the nearest tag from `color` and apply it.
    static func applyTag(for color: StyleColor, to url: URL) throws {
        try setTag(nearestTag(to: color), on: url)
    }

    /// Convenience: derive the tag color from a Style's fill (using the
    /// first stop for gradients) and apply it, if the style opted in.
    static func applyTagIfRequested(for style: Style, to url: URL) throws {
        guard style.applyColorTag else { return }
        let color: StyleColor
        switch style.fill {
        case .solid(let c): color = c
        case .gradient(let c, _, _): color = c
        }
        try applyTag(for: color, to: url)
    }
}
