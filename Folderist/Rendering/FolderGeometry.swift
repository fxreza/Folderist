import AppKit
import CoreGraphics

/// Resolution-independent layout of our original macOS-style folder shape.
///
/// This is the **fallback** base folder: the renderer prefers the real bitmap (`BaseFolderArt`)
/// and only falls back to this vector when neither user artwork nor the system icon is
/// available. The proportions here also supply the defaults the bitmap measurement falls back on.
///
/// All coordinates use a **top-left origin** (y grows downward), matching the flipped
/// contexts produced by `Raster.context`. Every measurement is a fraction of the canvas,
/// so the same code produces a crisp 16 px icon and a 1024 px master.
///
/// The proportions below were measured off the system folder icon rendered at 1024 px
/// (`GenericFolderIcon.iconset/icon_512x512@2x.png`) by sub-pixel alpha-edge detection.
/// The raw numbers, in 1024-px units, are quoted next to each constant. Nothing from the
/// system artwork is copied — this is our own vector rebuilt to the same measurements.
struct FolderGeometry {
    let canvas: CGFloat

    // Horizontal extent of the folder.
    let left: CGFloat
    let right: CGFloat
    /// Top of the raised back panel (the tab).
    let backTop: CGFloat
    /// Top of the back panel to the right of the tab — the "shoulder".
    /// The system folder has a visible band of back panel between this and `frontTop`.
    let shoulderTop: CGFloat
    /// Top edge of the front panel.
    let frontTop: CGFloat
    let bottom: CGFloat

    /// Corner radius at the two bottom corners.
    let bottomRadius: CGFloat
    /// Corner radius at the front panel's top corners and at the shoulder's top-right corner.
    let topRadius: CGFloat
    /// Corner radius at the tab's top-left corner.
    let tabRadius: CGFloat
    /// Where the raised tab hands over to the shoulder.
    let tabRight: CGFloat
    /// Horizontal length of the S-curve between the tab top and the shoulder.
    let tabSlant: CGFloat

    /// Height of one of the stacked "sheet" bands along the bottom of the front panel.
    let lipHeight: CGFloat
    /// How many of those bands the front panel ends with.
    let lipCount: Int

    // MARK: Measured proportions (fractions of the canvas / of the folder width)

    /// x = 39.21 / 1024
    static let leftFraction: CGFloat = 0.038286
    /// x = 986.80 / 1024
    static let rightFraction: CGFloat = 0.963667
    /// y = 139.23 / 1024
    static let backTopFraction: CGFloat = 0.135964
    /// y = 213.26 / 1024
    static let shoulderTopFraction: CGFloat = 0.208259
    /// y = 258.40 / 1024 — the system icon softens this edge over ~2 px; this is its centroid.
    static let frontTopFraction: CGFloat = 0.252344
    /// y = 882.81 / 1024
    static let bottomFraction: CGFloat = 0.862117

    /// r = 28 / 947.59 (folder width)
    static let bottomRadiusFraction: CGFloat = 0.029548
    /// r = 50 / 947.59
    static let topRadiusFraction: CGFloat = 0.052765
    /// r = 49 / 947.59
    static let tabRadiusFraction: CGFloat = 0.051710
    /// (404 − 39.21) / 947.59
    static let tabRightFraction: CGFloat = 0.384971
    /// 99 / 947.59
    static let tabSlantFraction: CGFloat = 0.104476
    /// 25.10 / 1024 — one third of the distance from y = 807.5 to the bottom edge.
    static let lipHeightFraction: CGFloat = 0.024514

    init(canvas: CGFloat) {
        self.canvas = canvas
        left = Self.leftFraction * canvas
        right = Self.rightFraction * canvas
        backTop = Self.backTopFraction * canvas
        shoulderTop = Self.shoulderTopFraction * canvas
        frontTop = Self.frontTopFraction * canvas
        bottom = Self.bottomFraction * canvas
        let w = right - left
        bottomRadius = Self.bottomRadiusFraction * w
        topRadius = Self.topRadiusFraction * w
        tabRadius = Self.tabRadiusFraction * w
        tabRight = left + Self.tabRightFraction * w
        tabSlant = Self.tabSlantFraction * w
        lipHeight = Self.lipHeightFraction * canvas
        lipCount = 3
    }

    var width: CGFloat { right - left }
    var height: CGFloat { bottom - backTop }

    /// Bounding box of the entire folder.
    var bounds: CGRect { CGRect(x: left, y: backTop, width: width, height: bottom - backTop) }

    /// The front panel rectangle — the usable area for overlays.
    var frontPanel: CGRect { CGRect(x: left, y: frontTop, width: width, height: bottom - frontTop) }

    /// Top of the stacked bands at the bottom of the front panel.
    var lipTop: CGFloat { bottom - lipHeight * CGFloat(lipCount) }

    /// The smooth part of the front panel, above the stacked bands.
    var frontBody: CGRect {
        CGRect(x: left, y: frontTop, width: width, height: lipTop - frontTop)
    }

    /// One rectangle per stacked band, top to bottom.
    var lipBands: [CGRect] {
        (0..<lipCount).map { i in
            CGRect(x: left, y: lipTop + CGFloat(i) * lipHeight, width: width, height: lipHeight)
        }
    }

    /// The visible band of back panel: the tab plus the shoulder, down to the front panel's top edge.
    var backPanelBand: CGRect {
        CGRect(x: left, y: backTop, width: width, height: frontTop - backTop)
    }

    /// Back panel + tab. This is also the full silhouette of the icon.
    var backPath: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: left, y: bottom - bottomRadius))
        p.addLine(to: CGPoint(x: left, y: backTop + tabRadius))
        p.addArc(tangent1End: CGPoint(x: left, y: backTop),
                 tangent2End: CGPoint(x: left + tabRadius, y: backTop),
                 radius: tabRadius)
        p.addLine(to: CGPoint(x: tabRight - tabSlant, y: backTop))
        // A symmetric S-curve down to the shoulder: both control points sit at the midpoint.
        // Fitting the system icon's own profile gave exactly this (rms 0.08 px at 1024).
        let mid = tabRight - tabSlant / 2
        p.addCurve(to: CGPoint(x: tabRight, y: shoulderTop),
                   control1: CGPoint(x: mid, y: backTop),
                   control2: CGPoint(x: mid, y: shoulderTop))
        p.addLine(to: CGPoint(x: right - topRadius, y: shoulderTop))
        p.addArc(tangent1End: CGPoint(x: right, y: shoulderTop),
                 tangent2End: CGPoint(x: right, y: shoulderTop + topRadius),
                 radius: topRadius)
        p.addLine(to: CGPoint(x: right, y: bottom - bottomRadius))
        p.addArc(tangent1End: CGPoint(x: right, y: bottom),
                 tangent2End: CGPoint(x: right - bottomRadius, y: bottom),
                 radius: bottomRadius)
        p.addLine(to: CGPoint(x: left + bottomRadius, y: bottom))
        p.addArc(tangent1End: CGPoint(x: left, y: bottom),
                 tangent2End: CGPoint(x: left, y: bottom - bottomRadius),
                 radius: bottomRadius)
        p.closeSubpath()
        return p
    }

    /// The front panel: a rounded rectangle, generous at the top, tighter at the bottom.
    var frontPath: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: left, y: frontTop + topRadius))
        p.addArc(tangent1End: CGPoint(x: left, y: frontTop),
                 tangent2End: CGPoint(x: left + topRadius, y: frontTop),
                 radius: topRadius)
        p.addLine(to: CGPoint(x: right - topRadius, y: frontTop))
        p.addArc(tangent1End: CGPoint(x: right, y: frontTop),
                 tangent2End: CGPoint(x: right, y: frontTop + topRadius),
                 radius: topRadius)
        p.addLine(to: CGPoint(x: right, y: bottom - bottomRadius))
        p.addArc(tangent1End: CGPoint(x: right, y: bottom),
                 tangent2End: CGPoint(x: right - bottomRadius, y: bottom),
                 radius: bottomRadius)
        p.addLine(to: CGPoint(x: left + bottomRadius, y: bottom))
        p.addArc(tangent1End: CGPoint(x: left, y: bottom),
                 tangent2End: CGPoint(x: left, y: bottom - bottomRadius),
                 radius: bottomRadius)
        p.closeSubpath()
        return p
    }

    /// Full silhouette (back panel and front panel share the same outline below `frontTop`).
    var silhouettePath: CGPath { backPath }
}
