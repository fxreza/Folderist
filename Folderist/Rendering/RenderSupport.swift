import AppKit
import CoreGraphics

// MARK: - Color helpers

extension StyleColor {
    /// The color as an sRGB `NSColor`.
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(c.redComponent),
                  green: Double(c.greenComponent),
                  blue: Double(c.blueComponent),
                  alpha: Double(c.alphaComponent))
    }
}

extension NSColor {
    /// Guaranteed-sRGB variant so component access is always safe.
    var srgb: NSColor { usingColorSpace(.sRGB) ?? NSColor.black }

    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let c = srgb
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    /// Multiplies the RGB channels (equivalent to scaling HSB brightness).
    func scalingBrightness(_ factor: CGFloat) -> NSColor {
        let c = rgba
        return NSColor(srgbRed: min(1, max(0, c.r * factor)),
                       green: min(1, max(0, c.g * factor)),
                       blue: min(1, max(0, c.b * factor)),
                       alpha: c.a)
    }

    func scalingSaturation(_ factor: CGFloat) -> NSColor {
        let c = srgb
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, max(0, s * factor)), brightness: b, alpha: a)
    }

    /// Linear mix toward another color. `fraction` 0 = self, 1 = other.
    func mixed(with other: NSColor, fraction: CGFloat) -> NSColor {
        let f = min(1, max(0, fraction))
        let a = rgba, b = other.rgba
        return NSColor(srgbRed: a.r + (b.r - a.r) * f,
                       green: a.g + (b.g - a.g) * f,
                       blue: a.b + (b.b - a.b) * f,
                       alpha: a.a + (b.a - a.a) * f)
    }

    /// Relative luminance (0…1) of the color, ignoring alpha.
    var luminance: CGFloat {
        let c = rgba
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    func withAlpha(_ alpha: CGFloat) -> NSColor {
        let c = rgba
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: min(1, max(0, alpha)))
    }
}

// MARK: - Raster helpers

enum Raster {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// A premultiplied-RGBA bitmap context with a top-left origin (y grows downward).
    static func context(pixelWidth: Int, pixelHeight: Int) -> CGContext? {
        let w = max(1, pixelWidth), h = max(1, pixelHeight)
        guard let ctx = CGContext(data: nil,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        // Flip so that all geometry can be expressed with a top-left origin.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        return ctx
    }

    /// Runs `body` with a flipped bitmap context installed as the current AppKit context,
    /// so `NSImage.draw` / `NSAttributedString.draw` land right-side-up.
    static func image(pixelWidth: Int, pixelHeight: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = context(pixelWidth: pixelWidth, pixelHeight: pixelHeight) else { return nil }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Draws a CGImage into a flipped context without vertically mirroring it.
    static func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext, alpha: CGFloat = 1.0) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Rasterizes an `NSImage` into an *unflipped* (AppKit-native, y-up) bitmap.
    ///
    /// `NSImage.draw(in:…)` mirrors its artwork vertically inside the destination rect when the
    /// current context is one of our top-left-origin contexts — it does not honour the
    /// `NSGraphicsContext(cgContext:flipped:)` flag for this call. Going through a plain,
    /// unflipped context is unambiguous, so this is the only place NSImage rasterization happens.
    static func rasterize(_ image: NSImage, pixelWidth: Int, pixelHeight: Int,
                          fraction: CGFloat = 1.0) -> CGImage? {
        let w = max(1, pixelWidth), h = max(1, pixelHeight)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                   from: .zero, operation: .sourceOver, fraction: fraction)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Draws an `NSImage` into a top-left-origin context, right-side-up.
    ///
    /// Use this instead of `NSImage.draw(in:…)` anywhere inside a `Raster.image` block —
    /// see `rasterize(_:pixelWidth:pixelHeight:fraction:)` for why.
    static func drawImage(_ image: NSImage, in rect: CGRect, ctx: CGContext, alpha: CGFloat = 1.0) {
        let w = Int(max(1, rect.width.rounded())), h = Int(max(1, rect.height.rounded()))
        guard let cg = rasterize(image, pixelWidth: w, pixelHeight: h) else { return }
        draw(cg, in: rect, ctx: ctx, alpha: alpha)
    }

    static func nsImage(_ image: CGImage, pointSize: CGSize) -> NSImage {
        let img = NSImage(cgImage: image, size: pointSize)
        return img
    }

    /// Aspect-fits `size` inside `rect`.
    static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Aspect-fills `rect` with `size` (overflow is expected to be clipped).
    static func fill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

// MARK: - Coverage (monochrome overlay shapes)

/// How an NSImage is converted into a monochrome coverage mask.
enum CoverageSource {
    /// The image's own alpha channel defines the shape (symbols, glyphs, text).
    case alpha
    /// Dark pixels define the shape (image "stamp" mode).
    case darkness
}

enum Coverage {
    /// Rasterizes `image` aspect-fit into a `pixelSize` bitmap and returns a CGImage whose
    /// alpha channel is the shape's coverage. RGB is irrelevant — everything is re-tinted.
    static func make(from image: NSImage, pixelSize: CGSize, source: CoverageSource) -> CGImage? {
        let w = max(1, Int(pixelSize.width.rounded())), h = max(1, Int(pixelSize.height.rounded()))
        guard let raw = Raster.image(pixelWidth: w, pixelHeight: h, { ctx in
            let box = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            var src = image.size
            if src.width <= 0 || src.height <= 0 { src = box.size }
            let target = Raster.fit(src, in: box)
            Raster.drawImage(image, in: target, ctx: ctx)
        }) else { return nil }

        switch source {
        case .alpha:
            return raw
        case .darkness:
            return darknessMask(from: raw)
        }
    }

    /// Converts an image into a mask where dark, opaque pixels are fully covered.
    static func darknessMask(from image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = Raster.context(pixelWidth: w, pixelHeight: h) else { return nil }
        ctx.saveGState()
        ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(h)))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.restoreGState()
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            let a = CGFloat(bytes[o + 3]) / 255
            guard a > 0 else { bytes[o] = 0; bytes[o + 1] = 0; bytes[o + 2] = 0; continue }
            // Un-premultiply, take darkness, re-premultiply as black.
            let r = CGFloat(bytes[o]) / 255 / a
            let g = CGFloat(bytes[o + 1]) / 255 / a
            let b = CGFloat(bytes[o + 2]) / 255 / a
            let lum = min(1, max(0, 0.2126 * r + 0.7152 * g + 0.0722 * b))
            let cov = a * (1 - lum)
            bytes[o] = 0; bytes[o + 1] = 0; bytes[o + 2] = 0
            bytes[o + 3] = UInt8(min(255, max(0, cov * 255)).rounded())
        }
        return ctx.makeImage()
    }

    /// Recolors a coverage mask with a flat color.
    static func tinted(_ coverage: CGImage, color: NSColor) -> CGImage? {
        let w = coverage.width, h = coverage.height
        return Raster.image(pixelWidth: w, pixelHeight: h) { ctx in
            let box = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            Raster.draw(coverage, in: box, ctx: ctx)
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(color.cgColor)
            ctx.fill(box)
            ctx.setBlendMode(.normal)
        }
    }

    private static let ringDirections: [CGPoint] = (0..<16).map {
        let a = CGFloat($0) / 16 * 2 * .pi
        return CGPoint(x: cos(a), y: sin(a))
    }

    /// Grows a coverage mask outward by `radius` pixels.
    static func dilated(_ coverage: CGImage, radius: CGFloat) -> CGImage? {
        let w = coverage.width, h = coverage.height
        return Raster.image(pixelWidth: w, pixelHeight: h) { ctx in
            let box = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            for d in ringDirections {
                Raster.draw(coverage, in: box.offsetBy(dx: d.x * radius, dy: d.y * radius), ctx: ctx)
            }
            Raster.draw(coverage, in: box, ctx: ctx)
        }
    }

    /// Shrinks a coverage mask inward by `radius` pixels.
    static func eroded(_ coverage: CGImage, radius: CGFloat) -> CGImage? {
        let w = coverage.width, h = coverage.height
        return Raster.image(pixelWidth: w, pixelHeight: h) { ctx in
            let box = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            Raster.draw(coverage, in: box, ctx: ctx)
            ctx.setBlendMode(.destinationIn)
            for d in ringDirections {
                Raster.draw(coverage, in: box.offsetBy(dx: d.x * radius, dy: d.y * radius), ctx: ctx)
            }
            ctx.setBlendMode(.normal)
        }
    }

    /// `a` with `b` punched out of it.
    static func subtracting(_ a: CGImage, _ b: CGImage, offset: CGPoint = .zero) -> CGImage? {
        let w = a.width, h = a.height
        return Raster.image(pixelWidth: w, pixelHeight: h) { ctx in
            let box = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            Raster.draw(a, in: box, ctx: ctx)
            ctx.setBlendMode(.destinationOut)
            Raster.draw(b, in: box.offsetBy(dx: offset.x, dy: offset.y), ctx: ctx)
            ctx.setBlendMode(.normal)
        }
    }
}
