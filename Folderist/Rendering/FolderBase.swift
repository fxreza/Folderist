import AppKit
import CoreGraphics

/// The base folder layer for one render — the user's bitmap when it exists, our vector when it
/// doesn't — behind one small interface: a layout box, two clipping masks, a body painter and a
/// colour probe.
///
/// Everything above this (overlays, text, effects) is written against `FolderBase` alone, so the
/// two pipelines can never drift: the same overlay code lays out, clips and embosses identically
/// whether the folder underneath is a bitmap or a path.
struct FolderBase {
    let canvas: CGFloat
    let geometry: FolderGeometry
    /// `nil` when no artwork is installed — the vector fallback.
    let art: BaseFolderArt?

    init(canvas: CGFloat, art: BaseFolderArt? = nil) {
        self.canvas = max(1, canvas)
        self.geometry = FolderGeometry(canvas: max(1, canvas))
        self.art = art
    }

    init(canvas: CGFloat, resources: RenderResources) {
        self.init(canvas: canvas, art: resources.baseFolderArt)
    }

    var usesBitmap: Bool { art != nil }

    private var side: Int { Int(max(1, canvas.rounded())) }

    private var canvasRect: CGRect { CGRect(x: 0, y: 0, width: canvas, height: canvas) }

    // MARK: - Layout

    /// Bounding box of the folder body.
    var bounds: CGRect {
        guard let art else { return geometry.bounds }
        let b = art.layout.bounds
        return CGRect(x: b.minX * canvas, y: b.minY * canvas,
                      width: b.width * canvas, height: b.height * canvas)
    }

    var width: CGFloat { bounds.width }

    /// The front panel — the usable area for overlays and text.
    var frontPanel: CGRect {
        guard let art else { return geometry.frontPanel }
        let b = bounds
        let top = art.layout.frontTop * canvas
        return CGRect(x: b.minX, y: top, width: b.width, height: max(1, b.maxY - top))
    }

    /// Corner radius of the front panel's top corners, in canvas units.
    private var frontPanelRadius: CGFloat {
        FolderGeometry.topRadiusFraction * width
    }

    // MARK: - Body

    /// Paints the folder itself.
    func draw(fill: FolderFill, into ctx: CGContext) {
        guard let art else {
            FolderIconRenderer.drawFolderBody(fill: resolved(fill), geo: geometry, ctx: ctx, canvas: canvas)
            return
        }
        // The artwork carries its own shading *and* its own drop shadow, so nothing is added.
        Raster.draw(art.rendered(side: side, fill: fill).image, in: canvasRect, ctx: ctx)
    }

    /// The default style means "the system folder", not "this particular blue". In bitmap mode
    /// that is the artwork, untouched; in vector mode it is the colour the shading model was
    /// fitted with — so retuning the `StyleColor.folderBlue` sentinel to match new artwork never
    /// drags the vector fallback's palette off the folder it was fitted to.
    private func resolved(_ fill: FolderFill) -> FolderFill {
        guard art == nil, BaseFolderArt.isDefaultFill(fill) else { return fill }
        return .solid(FolderIconRenderer.Shading.fittedBase)
    }

    // MARK: - Masks

    /// Coverage mask of the whole folder silhouette (never the drop shadow).
    func silhouetteCoverage() -> CGImage? {
        if let art { return art.silhouetteCoverage(side: side) }
        return coverage(of: geometry.silhouettePath)
    }

    /// Coverage mask of the front panel only.
    func frontPanelCoverage() -> CGImage? {
        guard art != nil else { return coverage(of: geometry.frontPath) }
        guard let silhouette = silhouetteCoverage() else { return nil }
        // The bitmap's silhouette below the panel's top edge *is* the panel, except for the
        // panel's own rounded top corners — so intersect with a rounded rect of the same radius.
        let panel = frontPanel
        let rounded = CGPath(roundedRect: CGRect(x: panel.minX, y: panel.minY,
                                                 width: panel.width,
                                                 height: panel.height + frontPanelRadius),
                             cornerWidth: frontPanelRadius, cornerHeight: frontPanelRadius,
                             transform: nil)
        return Raster.image(pixelWidth: side, pixelHeight: side) { ctx in
            Raster.draw(silhouette, in: canvasRect, ctx: ctx)
            ctx.setBlendMode(.destinationIn)
            ctx.addPath(rounded)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.setBlendMode(.normal)
        }
    }

    private func coverage(of path: CGPath) -> CGImage? {
        Raster.image(pixelWidth: side, pixelHeight: side) { ctx in
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - Colour probes

    /// The colour the folder actually shows at `point` — sampled from the recoloured bitmap in
    /// bitmap mode, derived from the fill in vector mode. Overlay tints and the engraved emboss
    /// are built from this, so they track the artwork's own shading.
    func color(of fill: FolderFill, at point: CGPoint) -> NSColor {
        if let art {
            let rendered = art.rendered(side: side, fill: fill)
            let scale = CGFloat(rendered.width) / canvas
            if let sampled = rendered.color(x: Int(point.x * scale), y: Int(point.y * scale)) {
                return sampled
            }
        }
        return FolderIconRenderer.baseColor(of: resolved(fill), at: point, in: bounds)
    }

    /// A single colour standing in for the whole folder (used where a per-pixel probe makes no
    /// sense, such as artwork drawn over the entire panel).
    func representativeColor(of fill: FolderFill) -> NSColor {
        let panel = frontPanel
        return color(of: fill, at: CGPoint(x: panel.midX, y: panel.midY))
    }
}
