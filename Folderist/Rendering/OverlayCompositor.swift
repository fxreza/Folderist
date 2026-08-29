import AppKit
import CoreGraphics

/// Builds the pixel artwork for a single overlay (symbol, glyph, stamp or text) with all
/// `OverlayEffects` baked in, ready to be rotated and composited onto the folder.
enum OverlayCompositor {

    /// Auto-derived colors for a monochrome overlay sitting on a folder of `base` color.
    struct Palette {
        var body: NSColor
        var embossHighlight: NSColor
        var outerStroke: NSColor
        var innerStroke: NSColor

        static func auto(base: NSColor, effects: OverlayEffects) -> Palette {
            let lum = base.luminance
            let engraved: NSColor
            if lum > 0.20 {
                engraved = base.scalingBrightness(0.62).scalingSaturation(1.10)
            } else {
                // On near-black folders an engraved glyph reads better slightly lighter.
                engraved = base.mixed(with: .white, fraction: 0.26)
            }
            let filled = base.mixed(with: .white, fraction: 0.84)
            let tint = effects.tint?.nsColor
            let body: NSColor
            if effects.fill {
                body = tint ?? filled
            } else if effects.emboss {
                body = tint ?? engraved
            } else {
                body = tint ?? engraved
            }
            return Palette(
                body: body,
                embossHighlight: base.mixed(with: .white, fraction: 0.62).withAlpha(0.85),
                outerStroke: (lum > 0.20 ? base.scalingBrightness(0.48) : base.mixed(with: .white, fraction: 0.5))
                    .withAlpha(0.90),
                innerStroke: base.mixed(with: .white, fraction: 0.66).withAlpha(0.80)
            )
        }
    }

    /// Result of compositing: artwork plus the padding (in canvas units) that was added
    /// around the requested rect to make room for shadow / outer stroke.
    struct Composite {
        var image: CGImage
        var padding: CGFloat
    }

    /// Renders a monochrome coverage mask with the requested effects.
    ///
    /// - Parameters:
    ///   - coverage: shape mask, sized in canvas units (1 px == 1 canvas unit).
    ///   - base: the folder color underneath the overlay, used for auto tints.
    static func monochrome(coverage: CGImage,
                           effects: OverlayEffects,
                           base: NSColor,
                           canvas: CGFloat) -> Composite? {
        var palette = Palette.auto(base: base, effects: effects)
        let w = coverage.width, h = coverage.height
        let minSide = CGFloat(min(w, h))

        // At Finder-list sizes an engraved rim is sub-pixel noise; trade it for flat contrast.
        let tiny = canvas < 48
        if tiny && effects.tint == nil && !effects.fill {
            palette.body = base.luminance > 0.20
                ? base.scalingBrightness(0.52).scalingSaturation(1.10)
                : base.mixed(with: .white, fraction: 0.42)
        }

        let embossOffset = max(1.0, 0.015 * minSide)
        let outerWidth = effects.outerStroke ? max(1.0, 0.026 * minSide) : 0
        let innerWidth = effects.innerStroke ? max(1.0, 0.022 * minSide) : 0
        let shadowBlur = effects.shadow ? max(1.5, 0.028 * canvas) : 0
        let shadowDrop = effects.shadow ? max(1.0, 0.014 * canvas) : 0

        let pad = ceil(max(shadowBlur * 1.6 + shadowDrop, outerWidth + 2, embossOffset + 2)) + 1
        let pw = w + Int(pad) * 2, ph = h + Int(pad) * 2
        let inner = CGRect(x: pad, y: pad, width: CGFloat(w), height: CGFloat(h))

        let useEmboss = effects.emboss && !effects.fill && !tiny

        guard let image = Raster.image(pixelWidth: pw, pixelHeight: ph, { ctx in
            // 1. Drop shadow (below everything).
            if effects.shadow,
               let blurred = ImageBlur.blurredAlpha(coverage, radius: shadowBlur),
               let shadow = Coverage.tinted(blurred, color: NSColor(white: 0, alpha: 0.38)) {
                Raster.draw(shadow, in: inner.offsetBy(dx: 0, dy: shadowDrop), ctx: ctx)
            }

            // 2. Outer stroke, behind the glyph body.
            if effects.outerStroke,
               let grown = Coverage.dilated(coverage, radius: outerWidth),
               let tinted = Coverage.tinted(grown, color: palette.outerStroke) {
                Raster.draw(tinted, in: inner, ctx: ctx)
            }

            // 3. Engraved highlight: a light rim just below the glyph, knocked out by the glyph itself.
            if useEmboss,
               let rim = Coverage.subtracting(coverage, coverage, offset: CGPoint(x: 0, y: -embossOffset)),
               let tinted = Coverage.tinted(rim, color: palette.embossHighlight) {
                Raster.draw(tinted, in: inner.offsetBy(dx: 0, dy: embossOffset), ctx: ctx)
            }

            // 4. Glyph body.
            if let body = Coverage.tinted(coverage, color: palette.body) {
                Raster.draw(body, in: inner, ctx: ctx)
            }

            // 5. Inner stroke, on top of the body.
            if effects.innerStroke,
               let shrunk = Coverage.eroded(coverage, radius: innerWidth),
               let ring = Coverage.subtracting(coverage, shrunk),
               let tinted = Coverage.tinted(ring, color: palette.innerStroke) {
                Raster.draw(tinted, in: inner, ctx: ctx)
            }
        }) else { return nil }

        return Composite(image: image, padding: pad)
    }

    /// Renders a full-color overlay (emoji artwork, user photo). `emboss` / `fill` /
    /// `innerStroke` do not apply to color artwork; shadow, opacity and outer stroke do.
    static func color(image: NSImage,
                      pixelSize: CGSize,
                      effects: OverlayEffects,
                      base: NSColor,
                      canvas: CGFloat,
                      aspect: CoverageFit = .fit) -> Composite? {
        let w = max(1, Int(pixelSize.width.rounded())), h = max(1, Int(pixelSize.height.rounded()))
        let minSide = CGFloat(min(w, h))
        let outerWidth = effects.outerStroke ? max(1.0, 0.026 * minSide) : 0
        let shadowBlur = effects.shadow ? max(1.5, 0.028 * canvas) : 0
        let shadowDrop = effects.shadow ? max(1.0, 0.014 * canvas) : 0
        let pad = ceil(max(shadowBlur * 1.6 + shadowDrop, outerWidth + 2)) + 1
        let pw = w + Int(pad) * 2, ph = h + Int(pad) * 2
        let inner = CGRect(x: pad, y: pad, width: CGFloat(w), height: CGFloat(h))

        let coverage: CGImage? = (effects.shadow || effects.outerStroke)
            ? Coverage.make(from: image, pixelSize: CGSize(width: w, height: h), source: .alpha)
            : nil
        let palette = Palette.auto(base: base, effects: effects)

        guard let out = Raster.image(pixelWidth: pw, pixelHeight: ph, { ctx in
            if effects.shadow, let coverage,
               let blurred = ImageBlur.blurredAlpha(coverage, radius: shadowBlur),
               let shadow = Coverage.tinted(blurred, color: NSColor(white: 0, alpha: 0.38)) {
                Raster.draw(shadow, in: inner.offsetBy(dx: 0, dy: shadowDrop), ctx: ctx)
            }
            if effects.outerStroke, let coverage,
               let grown = Coverage.dilated(coverage, radius: outerWidth),
               let tinted = Coverage.tinted(grown, color: palette.outerStroke) {
                Raster.draw(tinted, in: inner, ctx: ctx)
            }
            var src = image.size
            if src.width <= 0 || src.height <= 0 { src = inner.size }
            let target: CGRect
            switch aspect {
            case .fit: target = Raster.fit(src, in: inner)
            case .fill: target = Raster.fill(src, in: inner)
            case .stretch: target = inner
            }
            ctx.saveGState()
            if aspect == .fill { ctx.clip(to: inner) }
            // `Raster.drawImage`, never `NSImage.draw` — the latter mirrors artwork vertically
            // inside a top-left-origin context.
            Raster.drawImage(image, in: target, ctx: ctx)
            ctx.restoreGState()
        }) else { return nil }

        return Composite(image: out, padding: pad)
    }

    enum CoverageFit { case fit, fill, stretch }
}

// MARK: - Blur

enum ImageBlur {
    /// Blurs the alpha channel of a premultiplied-black coverage image with three box passes
    /// (a good Gaussian approximation) and returns a new coverage image. Deterministic, no GPU.
    static func blurredAlpha(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, radius >= 0.5 else { return image }
        guard let ctx = Raster.context(pixelWidth: w, pixelHeight: h) else { return nil }
        ctx.saveGState()
        ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(h)))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.restoreGState()
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var alpha = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { alpha[i] = Float(bytes[i * 4 + 3]) / 255 }

        var scratch = [Float](repeating: 0, count: w * h)
        let r = max(1, Int((radius * 0.6).rounded()))
        for _ in 0..<3 {
            boxBlurHorizontal(&alpha, into: &scratch, width: w, height: h, radius: r)
            boxBlurVertical(&scratch, into: &alpha, width: w, height: h, radius: r)
        }

        for i in 0..<(w * h) {
            let a = UInt8(min(255, max(0, alpha[i] * 255)).rounded())
            bytes[i * 4] = 0; bytes[i * 4 + 1] = 0; bytes[i * 4 + 2] = 0; bytes[i * 4 + 3] = a
        }
        return ctx.makeImage()
    }

    private static func boxBlurHorizontal(_ src: inout [Float], into dst: inout [Float],
                                          width w: Int, height h: Int, radius r: Int) {
        let window = Float(r * 2 + 1)
        for y in 0..<h {
            let row = y * w
            var sum: Float = 0
            for x in -r...r { sum += src[row + min(w - 1, max(0, x))] }
            for x in 0..<w {
                dst[row + x] = sum / window
                let out = min(w - 1, max(0, x - r))
                let inn = min(w - 1, max(0, x + r + 1))
                sum += src[row + inn] - src[row + out]
            }
        }
    }

    private static func boxBlurVertical(_ src: inout [Float], into dst: inout [Float],
                                        width w: Int, height h: Int, radius r: Int) {
        let window = Float(r * 2 + 1)
        for x in 0..<w {
            var sum: Float = 0
            for y in -r...r { sum += src[min(h - 1, max(0, y)) * w + x] }
            for y in 0..<h {
                dst[y * w + x] = sum / window
                let out = min(h - 1, max(0, y - r))
                let inn = min(h - 1, max(0, y + r + 1))
                sum += src[inn * w + x] - src[out * w + x]
            }
        }
    }
}
