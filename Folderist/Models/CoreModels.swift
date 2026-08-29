import Foundation

// MARK: - Core data model (shared contract — all modules code against these types)

/// A color stored device-independently.
struct StyleColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1.0

    /// The dominant base colour of this Mac's system folder icon (measured via
    /// `BaseFolderArt.dominantColor()` from the runtime `NSWorkspace` folder icon).
    /// A solid fill equal to this value is treated as "default" and renders the
    /// system artwork untouched; the vector fallback uses its own fitted base.
    static let folderBlue = StyleColor(red: 0.3593, green: 0.7473, blue: 0.9223)
}

/// Base fill of the folder: single color or a two-stop linear gradient.
enum FolderFill: Codable, Equatable, Hashable {
    case solid(StyleColor)
    case gradient(StyleColor, StyleColor, angleDegrees: Double)
}

/// Placement of an overlay on the 1024x1024 icon canvas.
/// Offsets are fractions of canvas size relative to center; scale 1.0 = default size.
struct OverlayTransform: Codable, Equatable, Hashable {
    var offsetX: Double = 0
    var offsetY: Double = 0
    var scale: Double = 1.0
    var rotationDegrees: Double = 0
}

/// Visual effects applied to an overlay.
struct OverlayEffects: Codable, Equatable, Hashable {
    var opacity: Double = 1.0
    var shadow: Bool = false
    var emboss: Bool = true       // engraved into the folder color (FolderMarker default look)
    var fill: Bool = false        // solid fill instead of engraved
    var innerStroke: Bool = false
    var outerStroke: Bool = false
    var tint: StyleColor? = nil   // nil = auto (derived darker/lighter folder color)
}

/// How a user image is composited (FolderMarker's four modes).
enum ImageMode: String, Codable, CaseIterable {
    case fill      // image fills the folder silhouette
    case over      // image composited over the folder
    case stamp     // black & white image engraved into the folder color
    case only      // image replaces the folder icon entirely
}

/// The graphic overlay of a style (at most one; combinable with a TextOverlay).
enum GraphicOverlay: Codable, Equatable, Hashable {
    case sfSymbol(name: String)
    case bundledSymbol(catalog: String, name: String)   // e.g. ("lucide", "camera")
    case emoji(String)                                   // rendered via system emoji font
    case image(fileName: String, mode: ImageMode)        // file stored inside the style's asset folder
}

/// Text stamped on the folder. Combinable with a GraphicOverlay, or used alone.
struct TextOverlay: Codable, Equatable, Hashable {
    var text: String
    var fontFamily: String = "Helvetica Neue"
    var fontFace: String = "Bold"        // display name of the face within the family
    /// Point size on the 1024 canvas. nil = auto-fit to the folder's usable area.
    var pointSize: Double? = nil
    var transform: OverlayTransform = OverlayTransform()
    var effects: OverlayEffects = OverlayEffects()
}

/// One saved folder-icon design — a tile in the grid.
struct Style: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var fill: FolderFill = .solid(.folderBlue)
    var graphic: GraphicOverlay? = nil
    var graphicTransform: OverlayTransform = OverlayTransform()
    var graphicEffects: OverlayEffects = OverlayEffects()
    var text: TextOverlay? = nil
    /// Also apply the closest-matching Finder color tag when applying this style.
    var applyColorTag: Bool = false
}

/// A named collection of up to `maxStyles` styles.
struct Asset: Codable, Equatable, Hashable, Identifiable {
    static let maxStyles = 40
    var id: UUID = UUID()
    var name: String
    var isLocked: Bool = false
    var styles: [Style] = []
}

/// Root persisted document.
struct Library: Codable, Equatable {
    var assets: [Asset] = []
    var selectedAssetID: UUID? = nil
    var formatVersion: Int = 1
}
