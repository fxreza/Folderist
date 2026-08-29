import AppKit
import CoreGraphics

/// Renders a `Style` into a folder icon.
///
/// The engine is pure: it takes a value-type `Style` plus a `RenderResources` provider and
/// returns images. Nothing here touches the UI, the filesystem or global state, so it can be
/// exercised straight from tests.
///
/// Everything is expressed as a fraction of the canvas, so a 16 px icon and a 1024 px master
/// are drawn by the same code and both stay crisp.
///
/// The folder underneath the overlays comes from `FolderBase`: the real macOS folder bitmap
/// (`BaseFolderArt`) when one is available, and the vector `FolderGeometry` shape when it isn't.
/// Overlay layout, clipping and engraving are written against `FolderBase` alone, so both
/// pipelines behave identically from here up.
///
/// Note: the public-facing types (`Style`, `OverlayEffects`, …) live in `CoreModels.swift` and
/// are module-internal, so this API is module-internal too.
enum FolderIconRenderer {

    /// Sizes produced by `renderIconSet` — the sizes an `.iconset` / `.icns` needs.
    static let iconSetSizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

    /// The design canvas all `OverlayTransform` point sizes are authored against.
    static let referenceCanvas: CGFloat = 1024

    // MARK: - Public API

    /// Renders `style` at `canvas` × `canvas` pixels.
    static func renderIcon(style: Style,
                           canvas: CGFloat = 1024,
                           resources: RenderResources) -> NSImage {
        let side = max(1, Int(canvas.rounded()))
        let c = CGFloat(side)
        let cg = Raster.image(pixelWidth: side, pixelHeight: side) { ctx in
            draw(style: style, canvas: c, resources: resources, into: ctx)
        }
        guard let cg else { return NSImage(size: CGSize(width: c, height: c)) }
        return Raster.nsImage(cg, pointSize: CGSize(width: c, height: c))
    }

    /// Renders the full icon set (16…1024) keyed by pixel size.
    static func renderIconSet(style: Style, resources: RenderResources) -> [Int: NSImage] {
        var out: [Int: NSImage] = [:]
        for size in iconSetSizes {
            out[size] = renderIcon(style: style, canvas: CGFloat(size), resources: resources)
        }
        return out
    }

    /// A single `NSImage` carrying every icon-set size as a separate representation —
    /// what you hand to `NSWorkspace.setIcon(_:forFile:)` or an `.icns` writer.
    static func renderMultiRepresentationImage(style: Style, resources: RenderResources) -> NSImage {
        let composite = NSImage(size: CGSize(width: referenceCanvas, height: referenceCanvas))
        for size in iconSetSizes {
            let img = renderIcon(style: style, canvas: CGFloat(size), resources: resources)
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = CGSize(width: size, height: size)
            composite.addRepresentation(rep)
        }
        return composite
    }

    // MARK: - Master draw

    static func draw(style: Style, canvas: CGFloat, resources: RenderResources, into ctx: CGContext) {
        let base = FolderBase(canvas: canvas, resources: resources)

        // "Image only" replaces the folder entirely.
        if case .image(let fileName, .only) = style.graphic {
            if let image = resources.userImage(named: fileName) {
                let box = CGRect(x: 0, y: 0, width: canvas, height: canvas).insetBy(dx: 0.05 * canvas, dy: 0.05 * canvas)
                let rect = transformed(box, style.graphicTransform, canvas: canvas)
                drawColorOverlay(image: image, rect: rect, effects: style.graphicEffects,
                                 transform: style.graphicTransform, base: representativeColor(of: style.fill),
                                 canvas: canvas, ctx: ctx, aspect: .fit)
            }
            drawText(style: style, base: base, canvas: canvas, ctx: ctx)
            return
        }

        base.draw(fill: style.fill, into: ctx)

        let hasText = !(style.text?.text.isEmpty ?? true)
        if let graphic = style.graphic {
            drawGraphic(graphic, style: style, base: base, canvas: canvas,
                        resources: resources, ctx: ctx, hasText: hasText)
        }
        drawText(style: style, base: base, canvas: canvas, ctx: ctx)
    }

    // MARK: - Shading model

    /// One stop of the folder's shading profile.
    ///
    /// The shading is expressed *relative to the base fill* so it works for any colour and for
    /// gradients: the rendered colour is `mix(base, white, white) * value`. Both operations are
    /// plain alpha composites (white at `white`, then black at `1 - value`), which keeps the
    /// whole model resolution-independent and fill-agnostic.
    ///
    /// The numbers were fitted, channel-wise least squares, against the system folder icon at
    /// 1024 px with `StyleColor.folderBlue` as the base (residual < 0.004 per channel).
    struct ShadeStop {
        var at: CGFloat
        var white: CGFloat
        var value: CGFloat

        init(_ at: CGFloat, _ white: CGFloat, _ value: CGFloat) {
            self.at = at; self.white = white; self.value = value
        }
    }

    enum Shading {
        /// The base colour the shading numbers below were fitted with.
        ///
        /// `StyleColor.folderBlue` is the *sentinel* for "the default style" and is retuned
        /// whenever the base artwork changes; this constant is a property of the vector shading
        /// model and never moves. The default style renders with it (see `FolderBase.draw`), so
        /// the vector fallback keeps reproducing the system folder's palette no matter what the
        /// sentinel is set to.
        static let fittedBase = StyleColor(red: 0.4153, green: 0.8146, blue: 1.0)

        /// The tab / shoulder. Flat: the system icon has no gradient up here at all.
        static let backPanelWhite: CGFloat = 0.2872
        static let backPanelValue: CGFloat = 1.0

        /// The smooth part of the front panel, from `frontTop` to `lipTop`.
        static let frontPanel: [ShadeStop] = [
            ShadeStop(0.00, 0.000, 0.9727),
            ShadeStop(0.08, 0.000, 0.9727),
            ShadeStop(0.20, 0.024, 0.9766),
            ShadeStop(0.35, 0.059, 0.9818),
            ShadeStop(0.50, 0.088, 0.9872),
            ShadeStop(0.64, 0.114, 0.9883),
            ShadeStop(0.80, 0.130, 0.9872),
            ShadeStop(0.86, 0.130, 0.9789),
            ShadeStop(0.93, 0.106, 0.9636),
            ShadeStop(1.00, 0.088, 0.9476)
        ]

        /// One of the stacked "sheet" bands the front panel ends with: a bright fold line at the
        /// top falling away to a dark crease at the bottom.
        static let lip: [ShadeStop] = [
            ShadeStop(0.00, 0.330, 0.9580),
            ShadeStop(0.04, 0.277, 0.9547),
            ShadeStop(0.09, 0.214, 0.9493),
            ShadeStop(0.13, 0.152, 0.9437),
            ShadeStop(0.17, 0.126, 0.9424),
            ShadeStop(0.25, 0.114, 0.9403),
            ShadeStop(0.33, 0.100, 0.9390),
            ShadeStop(0.45, 0.081, 0.9357),
            ShadeStop(0.53, 0.064, 0.9333),
            ShadeStop(0.65, 0.034, 0.9306),
            ShadeStop(0.77, 0.014, 0.9254),
            ShadeStop(0.87, 0.000, 0.9227),
            ShadeStop(0.91, 0.000, 0.9090),
            ShadeStop(0.95, 0.000, 0.8733),
            ShadeStop(1.00, 0.000, 0.8398)
        ]

        /// Soft drop shadow, matching the one baked into the system icon.
        /// Fitted as a Gaussian: σ = 9.7 px, offset 8.7 px down, peak alpha 0.30 at 1024.
        static let shadowSigma: CGFloat = 0.00947
        static let shadowOffset: CGFloat = 0.0085
        static let shadowAlpha: CGFloat = 0.30
    }

    // MARK: - Base folder

    /// Draws the vector folder: drop shadow, base fill, back-panel shade, front-panel shading.
    ///
    /// This is the fallback path — reached through `FolderBase` when there is no base bitmap.
    static func drawFolderBody(fill: FolderFill, geo: FolderGeometry, ctx: CGContext, canvas: CGFloat) {
        let silhouette = geo.silhouettePath

        // 1. The soft shadow the icon casts, clipped to the outside of the silhouette so the
        //    body's own antialiased edge isn't darkened by the shadow's fill.
        drawDropShadow(silhouette: silhouette, canvas: canvas, ctx: ctx)

        // 2. Base color / gradient across the whole silhouette.
        ctx.saveGState()
        ctx.addPath(silhouette)
        ctx.clip()
        fillBase(fill, in: geo.bounds, ctx: ctx)

        // 3. Back panel (tab + shoulder): a flat, lighter shade of the base. Clipping *out* the
        //    front panel rather than clipping to a band keeps the front panel's rounded top
        //    corners showing back-panel colour, exactly as the system icon does.
        ctx.saveGState()
        ctx.addRect(CGRect(x: -canvas, y: -canvas, width: canvas * 3, height: canvas * 3))
        ctx.addPath(geo.frontPath)
        ctx.clip(using: .evenOdd)
        fillShade(white: Shading.backPanelWhite, value: Shading.backPanelValue,
                  in: geo.bounds, ctx: ctx)
        ctx.restoreGState()

        // 4. Front panel: one smooth gradient, then the stacked bands along the bottom.
        ctx.saveGState()
        ctx.addPath(geo.frontPath)
        ctx.clip()
        applyShade(Shading.frontPanel, in: geo.frontBody, ctx: ctx)
        for band in geo.lipBands {
            applyShade(Shading.lip, in: band, ctx: ctx)
        }
        ctx.restoreGState()

        ctx.restoreGState()
    }

    /// Composites `stops` over whatever is already in `rect`, clipped to `rect`.
    static func applyShade(_ stops: [ShadeStop], in rect: CGRect, ctx: CGContext) {
        guard !stops.isEmpty, rect.height > 0 else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        let locations = stops.map(\.at)
        drawVerticalGradient(colors: stops.map { NSColor(white: 1, alpha: min(1, max(0, $0.white))) },
                             locations: locations, in: rect, ctx: ctx)
        drawVerticalGradient(colors: stops.map { NSColor(white: 0, alpha: min(1, max(0, 1 - $0.value))) },
                             locations: locations, in: rect, ctx: ctx)
        ctx.restoreGState()
    }

    /// The flat version of `applyShade`.
    static func fillShade(white: CGFloat, value: CGFloat, in rect: CGRect, ctx: CGContext) {
        if white > 0 {
            ctx.setFillColor(NSColor(white: 1, alpha: min(1, max(0, white))).cgColor)
            ctx.fill(rect)
        }
        if value < 1 {
            ctx.setFillColor(NSColor(white: 0, alpha: min(1, max(0, 1 - value))).cgColor)
            ctx.fill(rect)
        }
    }

    /// The icon's own drop shadow. Painted only *outside* the silhouette, so the folder's
    /// antialiased edge blends with the shadow instead of with an opaque black fill.
    static func drawDropShadow(silhouette: CGPath, canvas: CGFloat, ctx: CGContext) {
        let blur = Shading.shadowSigma * canvas * 2.0   // CG's blur parameter ≈ 2σ
        guard blur > 0.05 else { return }
        ctx.saveGState()
        // Even-odd clip of "everything" against the silhouette leaves only the outside.
        ctx.addRect(CGRect(x: -canvas, y: -canvas, width: canvas * 3, height: canvas * 3))
        ctx.addPath(silhouette)
        ctx.clip(using: .evenOdd)
        // The context's CTM is flipped (y grows downward), so a *negative* user-space dy moves
        // the shadow down on screen.
        ctx.setShadow(offset: CGSize(width: 0, height: -Shading.shadowOffset * canvas),
                      blur: blur,
                      color: NSColor(white: 0, alpha: Shading.shadowAlpha).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(silhouette)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - Fill helpers

    static func fillBase(_ fill: FolderFill, in bounds: CGRect, ctx: CGContext) {
        switch fill {
        case .solid(let color):
            ctx.setFillColor(color.nsColor.cgColor)
            ctx.fill(bounds.insetBy(dx: -bounds.width, dy: -bounds.height))
        case .gradient(let a, let b, let angle):
            let (start, end) = gradientEndpoints(angleDegrees: angle, in: bounds)
            let colors = [a.nsColor.srgb.cgColor, b.nsColor.srgb.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: Raster.colorSpace, colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// Gradient axis for `angleDegrees` in a top-left-origin space: 0° points right, 90° points up.
    static func gradientEndpoints(angleDegrees: Double, in bounds: CGRect) -> (CGPoint, CGPoint) {
        let a = CGFloat(angleDegrees) * .pi / 180
        let dir = CGPoint(x: cos(a), y: -sin(a))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)
        ]
        var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
        for c in corners {
            let t = (c.x - center.x) * dir.x + (c.y - center.y) * dir.y
            lo = min(lo, t); hi = max(hi, t)
        }
        return (CGPoint(x: center.x + dir.x * lo, y: center.y + dir.y * lo),
                CGPoint(x: center.x + dir.x * hi, y: center.y + dir.y * hi))
    }

    /// Colour of the base fill at a point — used to derive automatic overlay tints.
    static func baseColor(of fill: FolderFill, at point: CGPoint, in bounds: CGRect) -> NSColor {
        switch fill {
        case .solid(let c):
            return c.nsColor
        case .gradient(let a, let b, let angle):
            let (start, end) = gradientEndpoints(angleDegrees: angle, in: bounds)
            let dx = end.x - start.x, dy = end.y - start.y
            let len2 = dx * dx + dy * dy
            guard len2 > 0 else { return a.nsColor }
            let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / len2))
            return a.nsColor.mixed(with: b.nsColor, fraction: t)
        }
    }

    static func representativeColor(of fill: FolderFill) -> NSColor {
        switch fill {
        case .solid(let c): return c.nsColor
        case .gradient(let a, let b, _): return a.nsColor.mixed(with: b.nsColor, fraction: 0.5)
        }
    }

    static func drawVerticalGradient(colors: [NSColor], locations: [CGFloat], in rect: CGRect, ctx: CGContext) {
        guard let gradient = CGGradient(colorsSpace: Raster.colorSpace,
                                        colors: colors.map { $0.srgb.cgColor } as CFArray,
                                        locations: locations) else { return }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // MARK: - Overlay layout

    /// Default (pre-transform) box for the graphic overlay.
    ///
    /// The layout is expressed against the folder's front panel and width, which the bitmap and
    /// vector pipelines both supply — so the same fractions place a symbol identically whether
    /// the folder underneath was measured off a bitmap or drawn from a path.
    static func graphicBox(panel: CGRect, width: CGFloat, withText: Bool) -> CGRect {
        let side = (withText ? 0.340 : 0.470) * width
        let centerY = panel.minY + (withText ? 0.325 : 0.500) * panel.height
        return CGRect(x: panel.midX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    static func graphicBox(base: FolderBase, withText: Bool) -> CGRect {
        graphicBox(panel: base.frontPanel, width: base.width, withText: withText)
    }

    static func graphicBox(geo: FolderGeometry, withText: Bool) -> CGRect {
        graphicBox(panel: geo.frontPanel, width: geo.width, withText: withText)
    }

    /// Default (pre-transform) box for the text overlay.
    static func textBox(panel: CGRect, width: CGFloat, withGraphic: Bool) -> CGRect {
        let w = (withGraphic ? 0.740 : 0.700) * width
        let h = (withGraphic ? 0.265 : 0.450) * panel.height
        let centerY = panel.minY + (withGraphic ? 0.775 : 0.500) * panel.height
        return CGRect(x: panel.midX - w / 2, y: centerY - h / 2, width: w, height: h)
    }

    static func textBox(base: FolderBase, withGraphic: Bool) -> CGRect {
        textBox(panel: base.frontPanel, width: base.width, withGraphic: withGraphic)
    }

    static func textBox(geo: FolderGeometry, withGraphic: Bool) -> CGRect {
        textBox(panel: geo.frontPanel, width: geo.width, withGraphic: withGraphic)
    }

    /// Applies scale + offset from an `OverlayTransform`. Rotation is applied at draw time.
    /// Positive `offsetY` moves the overlay down (SwiftUI convention).
    static func transformed(_ box: CGRect, _ t: OverlayTransform, canvas: CGFloat) -> CGRect {
        let s = CGFloat(max(0.01, min(20, t.scale)))
        let w = box.width * s, h = box.height * s
        return CGRect(x: box.midX - w / 2 + CGFloat(t.offsetX) * canvas,
                      y: box.midY - h / 2 + CGFloat(t.offsetY) * canvas,
                      width: w, height: h)
    }

    // MARK: - Graphic overlays

    @discardableResult
    static func drawGraphic(_ graphic: GraphicOverlay,
                            style: Style,
                            base: FolderBase,
                            canvas: CGFloat,
                            resources: RenderResources,
                            ctx: CGContext,
                            hasText: Bool) -> Bool {
        let effects = style.graphicEffects
        let transform = style.graphicTransform

        switch graphic {
        case .sfSymbol(let name):
            guard let symbol = sfSymbolImage(named: name, canvas: canvas) else { return false }
            let rect = transformed(graphicBox(base: base, withText: hasText), transform, canvas: canvas)
            drawMonochromeOverlay(source: symbol, coverageSource: .alpha, rect: rect,
                                  style: style, effects: effects, transform: transform,
                                  base: base, canvas: canvas, ctx: ctx)
            return true

        case .bundledSymbol(let catalog, let name):
            guard let image = resources.symbolImage(catalog: catalog, name: name) else { return false }
            let rect = transformed(graphicBox(base: base, withText: hasText), transform, canvas: canvas)
            drawMonochromeOverlay(source: image, coverageSource: .alpha, rect: rect,
                                  style: style, effects: effects, transform: transform,
                                  base: base, canvas: canvas, ctx: ctx)
            return true

        case .emoji(let emoji):
            guard let image = resources.emojiImage(for: emoji) ?? emojiImage(emoji, canvas: canvas) else { return false }
            let rect = transformed(graphicBox(base: base, withText: hasText), transform, canvas: canvas)
            drawColorOverlay(image: image, rect: rect, effects: effects, transform: transform,
                             base: base.color(of: style.fill, at: CGPoint(x: rect.midX, y: rect.midY)),
                             canvas: canvas, ctx: ctx, aspect: .fit)
            return true

        case .image(let fileName, let mode):
            guard let image = resources.userImage(named: fileName) else { return false }
            switch mode {
            case .only:
                return false // handled before the folder is drawn
            case .fill:
                let rect = transformed(base.frontPanel, transform, canvas: canvas)
                clipped(to: base.frontPanelCoverage(), canvas: canvas, ctx: ctx) { layer in
                    drawColorOverlay(image: image, rect: rect, effects: effects, transform: transform,
                                     base: base.representativeColor(of: style.fill),
                                     canvas: canvas, ctx: layer, aspect: .fill)
                }
                return true
            case .over:
                let panel = base.frontPanel
                let box = panel.insetBy(dx: 0.06 * base.width, dy: 0.06 * panel.height)
                let rect = transformed(box, transform, canvas: canvas)
                // Zooming in and panning is how the user chooses the crop, so anything that
                // lands outside the folder silhouette must be cut away.
                clipped(to: base.silhouetteCoverage(), canvas: canvas, ctx: ctx) { layer in
                    drawColorOverlay(image: image, rect: rect, effects: effects, transform: transform,
                                     base: base.representativeColor(of: style.fill),
                                     canvas: canvas, ctx: layer, aspect: .fit)
                }
                return true
            case .stamp:
                let rect = transformed(graphicBox(base: base, withText: hasText), transform, canvas: canvas)
                // A stamp is engraved *into* the folder, so — exactly like `.over` — anything the
                // user's scale or offset pushes past the silhouette has to be cropped away.
                clipped(to: base.silhouetteCoverage(), canvas: canvas, ctx: ctx) { layer in
                    drawMonochromeOverlay(source: image, coverageSource: .darkness, rect: rect,
                                          style: style, effects: effects, transform: transform,
                                          base: base, canvas: canvas, ctx: layer)
                }
                return true
            }
        }
    }

    /// Draws `body` into an off-screen layer, crops the layer to `coverage`, and composites the
    /// result with `.sourceAtop`.
    ///
    /// Two properties matter and neither survives a plain clip: the artwork is cropped to the
    /// folder's *body* (never the baked drop shadow, which a path clip knows nothing about), and
    /// `.sourceAtop` leaves the icon's alpha channel exactly as the folder painted it, so a crop
    /// running over the silhouette can't thicken its antialiased edge.
    static func clipped(to coverage: CGImage?, canvas: CGFloat, ctx: CGContext,
                        _ body: (CGContext) -> Void) {
        guard let coverage else { body(ctx); return }
        let side = Int(max(1, canvas.rounded()))
        let box = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        guard let layer = Raster.image(pixelWidth: side, pixelHeight: side, { layerCtx in
            body(layerCtx)
            layerCtx.setBlendMode(.destinationIn)
            Raster.draw(coverage, in: box, ctx: layerCtx)
            layerCtx.setBlendMode(.normal)
        }) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)
        Raster.draw(layer, in: box, ctx: ctx)
        ctx.restoreGState()
    }

    /// Rasterizes `source` into a coverage mask, applies the effects, and composites it.
    static func drawMonochromeOverlay(source: NSImage,
                                      coverageSource: CoverageSource,
                                      rect: CGRect,
                                      style: Style,
                                      effects: OverlayEffects,
                                      transform: OverlayTransform,
                                      base: FolderBase,
                                      canvas: CGFloat,
                                      ctx: CGContext) {
        let pixelSize = clampedPixelSize(rect.size, canvas: canvas)
        guard pixelSize.width >= 1, pixelSize.height >= 1,
              let coverage = Coverage.make(from: source, pixelSize: pixelSize, source: coverageSource) else { return }
        // The engraved look is derived from the colour the folder actually shows underneath the
        // overlay — sampled from the recoloured bitmap when there is one.
        let underneath = base.color(of: style.fill, at: CGPoint(x: rect.midX, y: rect.midY))
        guard let comp = OverlayCompositor.monochrome(coverage: coverage, effects: effects,
                                                      base: underneath, canvas: canvas) else { return }
        let scale = rect.width / max(1, pixelSize.width)
        let pad = comp.padding * scale
        let target = rect.insetBy(dx: -pad, dy: -pad)
        composite(comp.image, in: target, rotation: transform.rotationDegrees,
                  opacity: effects.opacity, ctx: ctx)
    }

    static func drawColorOverlay(image: NSImage,
                                 rect: CGRect,
                                 effects: OverlayEffects,
                                 transform: OverlayTransform,
                                 base: NSColor,
                                 canvas: CGFloat,
                                 ctx: CGContext,
                                 aspect: OverlayCompositor.CoverageFit) {
        let pixelSize = clampedPixelSize(rect.size, canvas: canvas)
        guard pixelSize.width >= 1, pixelSize.height >= 1,
              let comp = OverlayCompositor.color(image: image, pixelSize: pixelSize, effects: effects,
                                                 base: base, canvas: canvas, aspect: aspect) else { return }
        let scale = rect.width / max(1, pixelSize.width)
        let pad = comp.padding * scale
        let target = rect.insetBy(dx: -pad, dy: -pad)
        composite(comp.image, in: target, rotation: transform.rotationDegrees,
                  opacity: effects.opacity, ctx: ctx)
    }

    /// Draws a prepared composite with rotation about its centre and a global opacity.
    static func composite(_ image: CGImage, in rect: CGRect, rotation: Double,
                          opacity: Double, ctx: CGContext) {
        let alpha = CGFloat(min(1, max(0, opacity)))
        guard alpha > 0 else { return }
        ctx.saveGState()
        if abs(rotation) > 0.001 {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            // Positive degrees rotate clockwise on screen (SwiftUI convention); the context is y-down.
            ctx.rotate(by: CGFloat(rotation) * .pi / 180)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }
        Raster.draw(image, in: rect, ctx: ctx, alpha: alpha)
        ctx.restoreGState()
    }

    /// Keeps overlay rasters within a sane budget when a style uses an extreme scale.
    static func clampedPixelSize(_ size: CGSize, canvas: CGFloat) -> CGSize {
        let cap = max(64, canvas * 3)
        let w = min(cap, max(1, size.width.rounded()))
        let h = min(cap, max(1, size.height.rounded()))
        return CGSize(width: w, height: h)
    }

    // MARK: - Symbols & emoji

    static func sfSymbolImage(named name: String, canvas: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: max(32, canvas * 0.45), weight: .regular)
        let configured = base.withSymbolConfiguration(config) ?? base
        configured.isTemplate = true
        return configured
    }

    static func emojiImage(_ emoji: String, canvas: CGFloat) -> NSImage? {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let size = max(32, canvas * 0.5)
        let font = NSFont(name: "Apple Color Emoji", size: size) ?? NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let string = NSAttributedString(string: trimmed, attributes: attrs)
        var bounds = string.size()
        if bounds.width < 1 || bounds.height < 1 { bounds = CGSize(width: size, height: size) }
        let w = Int(ceil(bounds.width)), h = Int(ceil(bounds.height))
        guard let cg = Raster.image(pixelWidth: w, pixelHeight: h, { _ in
            string.draw(in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        }) else { return nil }
        return Raster.nsImage(cg, pointSize: CGSize(width: w, height: h))
    }

    // MARK: - Text

    /// Everything a caller (or a test) needs to know about how auto-fit resolved.
    struct TextMetrics {
        /// Resolved point size in canvas units.
        var pointSize: CGFloat
        /// Measured size of the rendered string at `pointSize`.
        var size: CGSize
        /// The size the text had to fit inside (auto-fit budget).
        var limit: CGSize
        /// The default layout box the text is centred in, before the overlay transform.
        var box: CGRect
        /// The folder's front panel.
        var panel: CGRect
        var didAutoFit: Bool
    }

    /// Resolves the font, the auto-fit point size and the measured text rect for a style.
    ///
    /// `base` supplies the layout box. Omitting it measures against the vector folder, which is
    /// what callers outside the render loop (editor previews, tests) want.
    static func textMetrics(for style: Style, canvas: CGFloat, base: FolderBase? = nil) -> TextMetrics? {
        guard let overlay = style.text, !overlay.text.isEmpty else { return nil }
        let base = base ?? FolderBase(canvas: canvas)
        let hasGraphic = style.graphic != nil && !isImageOnly(style.graphic)
        let box = textBox(base: base, withGraphic: hasGraphic)
        let limit = CGSize(width: box.width, height: box.height)

        if let requested = overlay.pointSize, requested > 0 {
            let size = CGFloat(requested) * canvas / referenceCanvas
            let font = resolveFont(family: overlay.fontFamily, face: overlay.fontFace, size: size)
            return TextMetrics(pointSize: size, size: measure(overlay.text, font: font),
                               limit: limit, box: box, panel: base.frontPanel, didAutoFit: false)
        }

        var lo: CGFloat = 2
        var hi: CGFloat = canvas
        var best: CGFloat = lo
        var bestSize = CGSize.zero
        for _ in 0..<40 {
            if hi - lo < 0.25 { break }
            let mid = (lo + hi) / 2
            let font = resolveFont(family: overlay.fontFamily, face: overlay.fontFace, size: mid)
            let measured = measure(overlay.text, font: font)
            if measured.width <= limit.width && measured.height <= limit.height {
                best = mid; bestSize = measured; lo = mid
            } else {
                hi = mid
            }
        }
        if bestSize == .zero {
            let font = resolveFont(family: overlay.fontFamily, face: overlay.fontFace, size: best)
            bestSize = measure(overlay.text, font: font)
        }
        return TextMetrics(pointSize: best, size: bestSize, limit: limit,
                           box: box, panel: base.frontPanel, didAutoFit: true)
    }

    static func drawText(style: Style, base: FolderBase, canvas: CGFloat, ctx: CGContext) {
        guard let overlay = style.text, !overlay.text.isEmpty,
              let metrics = textMetrics(for: style, canvas: canvas, base: base) else { return }
        let font = resolveFont(family: overlay.fontFamily, face: overlay.fontFace, size: metrics.pointSize)
        let drawSize = CGSize(width: max(1, ceil(metrics.size.width)), height: max(1, ceil(metrics.size.height)))
        let natural = CGRect(x: metrics.box.midX - drawSize.width / 2,
                             y: metrics.box.midY - drawSize.height / 2,
                             width: drawSize.width, height: drawSize.height)
        let rect = transformed(natural, overlay.transform, canvas: canvas)

        let pixelSize = clampedPixelSize(drawSize, canvas: canvas)
        guard let coverage = Raster.image(pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height), { _ in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byClipping
            let string = NSAttributedString(string: overlay.text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ])
            string.draw(with: CGRect(origin: .zero, size: pixelSize),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        }) else { return }

        let underneath = base.color(of: style.fill, at: CGPoint(x: rect.midX, y: rect.midY))
        guard let comp = OverlayCompositor.monochrome(coverage: coverage, effects: overlay.effects,
                                                      base: underneath, canvas: canvas) else { return }
        let scale = rect.width / max(1, pixelSize.width)
        let pad = comp.padding * scale
        composite(comp.image, in: rect.insetBy(dx: -pad, dy: -pad),
                  rotation: overlay.transform.rotationDegrees,
                  opacity: overlay.effects.opacity, ctx: ctx)
    }

    static func measure(_ text: String, font: NSFont) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let string = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let rect = string.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                    height: CGFloat.greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// Resolves a family + face display name (as offered by `NSFontManager`) into a concrete font.
    static func resolveFont(family: String, face: String, size: CGFloat) -> NSFont {
        let size = max(1, size)
        let manager = NSFontManager.shared
        if let members = manager.availableMembers(ofFontFamily: family) {
            // 1. Exact face-name match.
            for member in members where member.count >= 4 {
                guard let faceName = member[1] as? String else { continue }
                if faceName.caseInsensitiveCompare(face) == .orderedSame,
                   let postScript = member[0] as? String,
                   let font = NSFont(name: postScript, size: size) {
                    return font
                }
            }
            // 2. Trait/weight based match through the font manager.
            for member in members where member.count >= 4 {
                guard let faceName = member[1] as? String,
                      faceName.caseInsensitiveCompare(face) == .orderedSame,
                      let weight = member[2] as? Int,
                      let traitsRaw = member[3] as? Int else { continue }
                if let font = manager.font(withFamily: family,
                                           traits: NSFontTraitMask(rawValue: UInt(traitsRaw)),
                                           weight: weight, size: size) {
                    return font
                }
            }
            // 3. Any member of the family.
            if let first = members.first, let postScript = first[0] as? String,
               let font = NSFont(name: postScript, size: size) {
                return font
            }
        }
        if let font = NSFont(name: family, size: size) { return font }
        let weight: NSFont.Weight = face.lowercased().contains("bold") ? .bold : .regular
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func isImageOnly(_ graphic: GraphicOverlay?) -> Bool {
        if case .image(_, .only) = graphic { return true }
        return false
    }
}
