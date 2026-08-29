import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// The base folder artwork — the real macOS folder bitmap every render is built from.
///
/// Three sources, in order:
///
/// 1. **User artwork**: `BaseFolder.png` (a square 1024 px master) or `BaseFolder.icns` dropped
///    into `Folderist/Resources/BaseFolder/`.
/// 2. **The system folder icon**, read off the running Mac at launch — never bundled, never
///    copied into the repo. Apple's artwork stays where Apple put it.
/// 3. **The vector `FolderGeometry` pipeline**, if both of those fail.
///
/// Two guarantees shape the design:
///
/// 1. **The default style is the artwork, untouched.** When the style's fill is
///    `StyleColor.folderBlue` (within `defaultFillEpsilon`) no recolouring runs at all — the
///    normalized master is copied out pixel for pixel.
/// 2. **Every other colour is a remap of the same pixels.** Recolouring works in HSB and only
///    ever rotates hue and scales saturation/brightness, so the artwork's folds, paper peek and
///    baked drop shadow survive intact.
///
/// Instances are immutable and internally synchronized; `shared(directory:)` keeps one per
/// directory so the measurement and the per-size rasters are computed once.
final class BaseFolderArt {

    // MARK: - Naming

    /// Directory the artwork is looked for in, relative to a resource root.
    static let directoryName = "BaseFolder"
    /// Base name of the primary artwork.
    static let primaryName = "BaseFolder"
    /// Base name of the optional alternate artwork (an empty folder, for example).
    static let alternateName = "BaseFolder-empty"
    /// Extensions accepted for the artwork, in priority order.
    static let extensions = ["icns", "png", "tiff", "tif", "heic"]

    /// Apple's own generic folder artwork, used when `NSWorkspace` hands back nothing large
    /// enough. Read at runtime; never copied anywhere.
    static let coreTypesBundlePath = "/System/Library/CoreServices/CoreTypes.bundle"
    static let systemFolderIconName = "GenericFolderIcon"

    /// Largest representation kept. The system icon offers 2048 too, which no icon size needs.
    static let maximumSide = 1024

    /// Where a piece of artwork came from.
    enum Source: Equatable {
        case file(URL)
        case systemWorkspace
        case systemBundle(URL)

        var description: String {
            switch self {
            case .file(let url): return url.path
            case .systemWorkspace: return "NSWorkspace.icon(for: .folder)"
            case .systemBundle(let url): return url.path
            }
        }

        var isSystem: Bool {
            if case .file = self { return false }
            return true
        }
    }

    // MARK: - Stored state

    /// Normalized artwork keyed by pixel size. A PNG contributes one entry; an `.icns`
    /// contributes one per representation, so each icon size can be exact rather than resampled.
    private let representations: [Int: CGImage]
    /// Pixel size of the largest representation.
    let masterSize: Int
    /// Where the artwork was loaded from, for diagnostics.
    let source: Source

    private let lock = NSLock()
    private var scaled: [Int: CGImage] = [:]
    private var renders: [RenderKey: Rendered] = [:]
    /// Least-recently-used order for `renders`; a 1024 px recolour is ~8 MB, so the cache is
    /// bounded rather than left to grow one entry per style the user scrolls past.
    private var renderOrder: [RenderKey] = []
    private var coverages: [Int: CGImage] = [:]
    private var measurement: Measurement?

    /// How many recoloured rasters to keep.
    static let renderCacheLimit = 8

    private init(representations: [Int: CGImage], source: Source) {
        self.representations = representations
        self.masterSize = representations.keys.max() ?? 0
        self.source = source
    }

    // MARK: - Loading

    /// Loads the artwork named `name` from `directory`, or `nil` when it isn't there.
    static func load(directory: URL, name: String = primaryName) -> BaseFolderArt? {
        let fm = FileManager.default
        for ext in extensions {
            let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
            guard fm.fileExists(atPath: url.path) else { continue }
            if let art = load(url: url) { return art }
        }
        return nil
    }

    /// Loads artwork from an explicit file.
    static func load(url: URL) -> BaseFolderArt? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return load(image: image, source: .file(url))
    }

    /// Turns an `NSImage` into per-size artwork.
    ///
    /// Every square representation is kept at its own pixel size, so an `.icns` (and the system
    /// icon, which is one) can serve each icon size from artwork drawn for that size instead of
    /// from a resample of the master.
    static func load(image: NSImage, source: Source) -> BaseFolderArt? {
        var reps: [Int: CGImage] = [:]
        var isNativeScale: [Int: Bool] = [:]
        for rep in image.representations {
            let side = rep.pixelsWide
            guard side > 0, side == rep.pixelsHigh, side <= maximumSide else { continue }
            // The same pixel size can arrive several times (a 512 pt @2x rep and a 1024 pt @1x
            // rep are both 1024 px). Prefer the one drawn at its native scale.
            let native = Int(rep.size.width.rounded()) == side
            if let existingIsNative = isNativeScale[side], existingIsNative || !native { continue }
            guard let cg = cgImage(of: rep, side: side) else { continue }
            reps[side] = cg
            isNativeScale[side] = native
        }
        if reps.isEmpty {
            // Vector or otherwise non-representable artwork: rasterize one master.
            let measured = Int(max(image.size.width, image.size.height).rounded())
            let target = measured > 0 ? min(maximumSide, max(16, measured)) : maximumSide
            guard let cg = Raster.rasterize(image, pixelWidth: target, pixelHeight: target),
                  let normalized = normalized(cg) else { return nil }
            reps[target] = normalized
        }
        return BaseFolderArt(representations: reps, source: source)
    }

    /// Rasterizes one representation at its own pixel size, right-side-up and in our format.
    private static func cgImage(of rep: NSImageRep, side: Int) -> CGImage? {
        if let bitmap = rep as? NSBitmapImageRep, let cg = bitmap.cgImage, let out = normalized(cg) {
            return out
        }
        // `NSISIconImageRep` and friends only draw. An *unflipped* context keeps them upright.
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: Raster.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        rep.draw(in: CGRect(x: 0, y: 0, width: side, height: side), from: .zero,
                 operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// The macOS folder icon as the running system draws it.
    ///
    /// `NSWorkspace` first — that is the icon Finder shows today. If it comes back without a
    /// large representation (a stub icon, a headless session), fall back to reading Apple's own
    /// `GenericFolderIcon.icns` out of `CoreTypes.bundle`. Either way the artwork is read at
    /// runtime from the user's Mac; nothing is copied into the app.
    static func system() -> BaseFolderArt? {
        cacheLock.lock()
        if let hit = cache[systemCacheKey] { cacheLock.unlock(); return hit }
        // Asking the icon services on every render would be wasteful; one failure is enough.
        if systemLookupFailed { cacheLock.unlock(); return nil }
        cacheLock.unlock()

        var made: BaseFolderArt?
        let workspaceIcon = NSWorkspace.shared.icon(for: UTType.folder)
        if let art = load(image: workspaceIcon, source: .systemWorkspace), art.masterSize >= 512 {
            made = art
        }
        if made == nil,
           let bundle = Bundle(path: coreTypesBundlePath),
           let url = bundle.url(forResource: systemFolderIconName, withExtension: "icns"),
           let art = load(url: url) {
            made = BaseFolderArt(representations: art.representations, source: .systemBundle(url))
        }
        guard let made else {
            cacheLock.lock(); systemLookupFailed = true; cacheLock.unlock()
            return nil
        }
        cacheLock.lock(); cache[systemCacheKey] = made; cacheLock.unlock()
        return made
    }

    /// Every directory the artwork may live in under `root`, most specific first.
    static func searchDirectories(under root: URL) -> [URL] {
        [root.appendingPathComponent(directoryName), root]
    }

    /// The first user-supplied artwork found in `roots`, caching one instance per source file.
    static func shared(roots: [URL], name: String = primaryName) -> BaseFolderArt? {
        let fm = FileManager.default
        for root in roots {
            for directory in searchDirectories(under: root) {
                for ext in extensions {
                    let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
                    guard fm.fileExists(atPath: url.path) else { continue }
                    return cached(url: url)
                }
            }
        }
        return nil
    }

    /// What the app renders on: the user's artwork if they supplied any, else the system icon.
    static func shared(roots: [URL], name: String = primaryName,
                       allowingSystemFallback: Bool) -> BaseFolderArt? {
        if let user = shared(roots: roots, name: name) { return user }
        return allowingSystemFallback ? system() : nil
    }

    private static let systemCacheKey = "\u{0}system"
    private static let cacheLock = NSLock()
    private static var cache: [String: BaseFolderArt] = [:]
    private static var systemLookupFailed = false

    static func cached(url: URL) -> BaseFolderArt? {
        cacheLock.lock()
        if let hit = cache[url.path] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        guard let art = load(url: url) else { return nil }
        cacheLock.lock()
        cache[url.path] = art
        cacheLock.unlock()
        return art
    }

    /// Drops every cached instance. Tests that write new artwork call this.
    static func clearCaches() {
        cacheLock.lock()
        cache.removeAll()
        systemLookupFailed = false
        cacheLock.unlock()
    }

    /// Redraws `image` into the renderer's own sRGB / premultiplied-last bitmap format, so
    /// everything downstream (recolouring, sampling, byte comparisons) sees one pixel layout.
    static func normalized(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        return Raster.image(pixelWidth: w, pixelHeight: h) { ctx in
            Raster.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), ctx: ctx)
        }
    }

    // MARK: - Sizes

    /// The artwork at its largest available size.
    var master: CGImage { representations[masterSize] ?? representations.values.first! }

    /// Pixel sizes the artwork can serve without resampling.
    var availableSides: [Int] { Array(representations.keys) }

    /// The file the artwork came from, when it came from one.
    var sourceURL: URL? {
        switch source {
        case .file(let url), .systemBundle(let url): return url
        case .systemWorkspace: return nil
        }
    }

    /// The artwork at `side` × `side` pixels: an exact representation when the source has one
    /// (any `.icns` size), otherwise a high-quality resample of the master.
    func image(side: Int) -> CGImage {
        let side = max(1, side)
        if let exact = representations[side] { return exact }
        lock.lock()
        if let hit = scaled[side] { lock.unlock(); return hit }
        lock.unlock()
        // Resample from the smallest representation that is still at least as large.
        let source = representations.keys.filter { $0 >= side }.min().flatMap { representations[$0] } ?? master
        let resized = Raster.image(pixelWidth: side, pixelHeight: side) { ctx in
            ctx.interpolationQuality = .high
            Raster.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)), ctx: ctx)
        } ?? source
        lock.lock(); scaled[side] = resized; lock.unlock()
        return resized
    }

    // MARK: - Measurement

    /// What an alpha/luminance scan of the master says about the artwork's layout and colour.
    struct Measurement {
        /// Bounding box of the opaque folder body, as fractions of the canvas.
        var bounds: CGRect
        /// Top edge of the front panel, as a fraction of the canvas.
        var frontTop: CGFloat
        /// Dominant hue/saturation/brightness of the coloured body.
        var hue: CGFloat
        var saturation: CGFloat
        var brightness: CGFloat
        /// Whether `frontTop` came from the artwork or from the vector fallback proportions.
        var frontTopMeasured: Bool
    }

    var layout: Measurement {
        lock.lock()
        if let hit = measurement { lock.unlock(); return hit }
        lock.unlock()
        let made = Self.measure(master)
        lock.lock(); measurement = made; lock.unlock()
        return made
    }

    /// The artwork's dominant colour — what `StyleColor.folderBlue` should be set to so that the
    /// default style short-circuits to the untouched bitmap.
    func dominantColor() -> StyleColor {
        let m = layout
        let (r, g, b) = hsbToRGB(h: m.hue, s: m.saturation, v: m.brightness)
        return StyleColor(red: Double(r), green: Double(g), blue: Double(b))
    }

    static func measure(_ image: CGImage) -> Measurement {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let px = rgbaBytes(of: image) else {
            return Measurement(bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                               frontTop: FolderGeometry.frontTopFraction,
                               hue: 0, saturation: 0, brightness: 1, frontTopMeasured: false)
        }

        var minX = w, maxX = -1, minY = h, maxY = -1
        // Circular mean of hue, weighted by saturation; plain means for saturation/brightness.
        var hx = 0.0, hy = 0.0, satSum = 0.0, briSum = 0.0, colourWeight = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let a = CGFloat(px[o + 3]) / 255
                guard a >= 0.5 else { continue }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                guard a >= 0.9 else { continue }
                let (r, g, b) = unpremultiplied(px, o, a)
                let (hue, s, v) = rgbToHSB(r: r, g: g, b: b)
                guard s >= 0.10 else { continue }
                let angle = Double(hue) * 2 * .pi
                hx += cos(angle) * Double(s)
                hy += sin(angle) * Double(s)
                satSum += Double(s)
                briSum += Double(v)
                colourWeight += 1
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return Measurement(bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                               frontTop: FolderGeometry.frontTopFraction,
                               hue: 0, saturation: 0, brightness: 1, frontTopMeasured: false)
        }

        let cw = CGFloat(w), ch = CGFloat(h)
        let bounds = CGRect(x: CGFloat(minX) / cw, y: CGFloat(minY) / ch,
                            width: CGFloat(maxX - minX + 1) / cw,
                            height: CGFloat(maxY - minY + 1) / ch)

        var hue: CGFloat = 0
        if hx != 0 || hy != 0 {
            var a = atan2(hy, hx) / (2 * .pi)
            if a < 0 { a += 1 }
            hue = CGFloat(a)
        }
        let saturation = colourWeight > 0 ? CGFloat(satSum / colourWeight) : 0
        let brightness = colourWeight > 0 ? CGFloat(briSum / colourWeight) : 1

        let (frontTop, measured) = frontPanelTop(px, width: w, height: h,
                                                 minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        return Measurement(bounds: bounds, frontTop: frontTop,
                           hue: hue, saturation: saturation, brightness: brightness,
                           frontTopMeasured: measured)
    }

    /// Finds the front panel's top edge: the sharpest downward luminance step in the upper part
    /// of the body, which is exactly the fold where the lighter tab hands over to the panel.
    /// Falls back to the vector proportions when the artwork has no such step.
    private static func frontPanelTop(_ px: [UInt8], width w: Int, height h: Int,
                                      minX: Int, maxX: Int, minY: Int, maxY: Int) -> (CGFloat, Bool) {
        let bodyWidth = maxX - minX + 1, bodyHeight = maxY - minY + 1
        let x0 = minX + bodyWidth * 3 / 10, x1 = minX + bodyWidth * 7 / 10
        guard x1 > x0, bodyHeight > 8 else { return (FolderGeometry.frontTopFraction, false) }

        // Mean luminance per row over the middle of the body, opaque pixels only.
        var rows = [Double](repeating: -1, count: h)
        for y in minY...maxY {
            var sum = 0.0, n = 0.0
            for x in x0...x1 {
                let o = (y * w + x) * 4
                let a = CGFloat(px[o + 3]) / 255
                guard a >= 0.9 else { continue }
                let (r, g, b) = unpremultiplied(px, o, a)
                sum += Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
                n += 1
            }
            rows[y] = n > 0 ? sum / n : -1
        }

        // The step lives in the top half of the body; look for the largest drop across 4 rows.
        let searchLo = minY + max(2, bodyHeight / 20)
        let searchHi = minY + bodyHeight / 2
        var bestY = -1, bestDrop = 0.0
        var y = searchLo
        while y <= searchHi {
            let above = rows[max(0, y - 2)], below = rows[min(h - 1, y + 2)]
            if above >= 0, below >= 0 {
                let drop = above - below
                if drop > bestDrop { bestDrop = drop; bestY = y }
            }
            y += 1
        }
        guard bestY >= 0, bestDrop > 0.015 else { return (FolderGeometry.frontTopFraction, false) }
        return (CGFloat(bestY) / CGFloat(h), true)
    }

    // MARK: - Rendering (recolour)

    /// One recoloured raster plus its pixels, so overlay code can sample the colour underneath.
    struct Rendered {
        let image: CGImage
        let width: Int
        let height: Int
        fileprivate let pixels: [UInt8]

        /// Straight (un-premultiplied) colour at a pixel; `nil` where the artwork is transparent.
        func color(x: Int, y: Int) -> NSColor? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let o = (y * width + x) * 4
            guard o + 3 < pixels.count else { return nil }
            let a = CGFloat(pixels[o + 3]) / 255
            guard a >= 0.5 else { return nil }
            let (r, g, b) = unpremultiplied(pixels, o, a)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    private struct RenderKey: Hashable {
        var side: Int
        var fill: FolderFill
    }

    /// How close a solid fill must be to `StyleColor.folderBlue` to count as "the default", and
    /// therefore to skip recolouring entirely.
    static let defaultFillEpsilon = 0.004

    /// True when `fill` is the untouched-artwork default.
    static func isDefaultFill(_ fill: FolderFill) -> Bool {
        guard case .solid(let c) = fill else { return false }
        let d = StyleColor.folderBlue
        return abs(c.red - d.red) <= defaultFillEpsilon
            && abs(c.green - d.green) <= defaultFillEpsilon
            && abs(c.blue - d.blue) <= defaultFillEpsilon
            && abs(c.alpha - d.alpha) <= defaultFillEpsilon
    }

    /// The artwork at `side` px, recoloured for `fill`. The default fill returns the artwork
    /// itself — the very same `CGImage`, so "untouched" is a fact of the pipeline, not a claim.
    func rendered(side: Int, fill: FolderFill) -> Rendered {
        let side = max(1, side)
        let key = RenderKey(side: side, fill: Self.isDefaultFill(fill) ? .solid(.folderBlue) : fill)
        lock.lock()
        if let hit = renders[key] {
            touch(key)
            lock.unlock()
            return hit
        }
        lock.unlock()

        let source = image(side: side)
        let made: Rendered
        if Self.isDefaultFill(fill) {
            made = Rendered(image: source, width: source.width, height: source.height,
                            pixels: Self.rgbaBytes(of: source) ?? [])
        } else {
            made = Self.recolour(source, fill: fill, base: layout)
        }
        lock.lock()
        renders[key] = made
        touch(key)
        while renderOrder.count > Self.renderCacheLimit {
            renders.removeValue(forKey: renderOrder.removeFirst())
        }
        lock.unlock()
        return made
    }

    /// Moves `key` to the most-recently-used end. Caller holds `lock`.
    private func touch(_ key: RenderKey) {
        if let i = renderOrder.firstIndex(of: key) { renderOrder.remove(at: i) }
        renderOrder.append(key)
    }

    /// Per-pixel HSB remap: rotate the base hue band onto the target hue, scale saturation and
    /// brightness by the target's ratio to the measured base, and leave everything else alone.
    ///
    /// Low-saturation pixels — the white paper peek, the neutral shadow — get their hue rotated
    /// (so any residual tint matches the new colour) but keep their saturation and brightness,
    /// which is what keeps the paper white and the shadow neutral.
    static func recolour(_ image: CGImage, fill: FolderFill, base: Measurement) -> Rendered {
        let w = image.width, h = image.height
        guard var px = rgbaBytes(of: image) else {
            return Rendered(image: image, width: w, height: h, pixels: [])
        }

        // Gradient axis, in the same top-left-origin pixel space as the buffer.
        let bounds = CGRect(x: base.bounds.minX * CGFloat(w), y: base.bounds.minY * CGFloat(h),
                            width: base.bounds.width * CGFloat(w), height: base.bounds.height * CGFloat(h))
        var start = CGPoint.zero, axisX: CGFloat = 0, axisY: CGFloat = 0, axisLength2: CGFloat = 0
        let targetA = TargetColor(fill: fill, endpoint: 0)
        var targetB = TargetColor(fill: fill, endpoint: 1)
        if case .gradient(_, _, let angle) = fill {
            let (s, e) = FolderIconRenderer.gradientEndpoints(angleDegrees: angle, in: bounds)
            start = s
            axisX = e.x - s.x
            axisY = e.y - s.y
            axisLength2 = axisX * axisX + axisY * axisY
        } else {
            targetB = targetA
        }

        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                let a = CGFloat(px[o + 3]) / 255
                guard a > 0 else { continue }
                let (r, g, b) = unpremultiplied(px, o, a)
                let (hue, sat, bri) = rgbToHSB(r: r, g: g, b: b)
                guard bri > 0 else { continue }

                let target: TargetColor
                if axisLength2 > 0 {
                    let t = min(1, max(0, ((CGFloat(x) + 0.5 - start.x) * axisX +
                                          (CGFloat(y) + 0.5 - start.y) * axisY) / axisLength2))
                    target = TargetColor.interpolated(targetA, targetB, t)
                } else {
                    target = targetA
                }

                // How much this pixel belongs to the folder's own colour.
                let hueWeight = sat < 0.05 ? 1 : bandWeight(hueDistance(hue, base.hue))
                let colourWeight = hueWeight * smoothstep(0.06, 0.22, sat)

                let newHue = rotate(hue, toward: target.hue, by: hueWeight)
                let satFactor = base.saturation > 0.01 ? target.saturation / base.saturation : 1
                let briFactor = base.brightness > 0.01 ? target.brightness / base.brightness : 1
                let newSat = clamp01(sat * (1 + colourWeight * (satFactor - 1)))
                let newBri = clamp01(bri * (1 + colourWeight * (briFactor - 1)))

                let (nr, ng, nb) = hsbToRGB(h: newHue, s: newSat, v: newBri)
                px[o] = byte(nr * a)
                px[o + 1] = byte(ng * a)
                px[o + 2] = byte(nb * a)
                // Alpha is never touched: the silhouette and the baked shadow stay identical.
            }
        }

        let out = imageFromBytes(px, width: w, height: h) ?? image
        return Rendered(image: out, width: w, height: h, pixels: px)
    }

    /// A hue/saturation/brightness target derived from one end of a fill.
    struct TargetColor {
        var hue: CGFloat
        var saturation: CGFloat
        var brightness: CGFloat

        init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
            self.hue = hue; self.saturation = saturation; self.brightness = brightness
        }

        init(fill: FolderFill, endpoint: Int) {
            let colour: StyleColor
            switch fill {
            case .solid(let c): colour = c
            case .gradient(let a, let b, _): colour = endpoint == 0 ? a : b
            }
            let (h, s, v) = rgbToHSB(r: CGFloat(colour.red), g: CGFloat(colour.green), b: CGFloat(colour.blue))
            self.init(hue: h, saturation: s, brightness: v)
        }

        static func interpolated(_ a: TargetColor, _ b: TargetColor, _ t: CGFloat) -> TargetColor {
            TargetColor(hue: rotate(a.hue, toward: b.hue, by: t),
                        saturation: a.saturation + (b.saturation - a.saturation) * t,
                        brightness: a.brightness + (b.brightness - a.brightness) * t)
        }
    }

    // MARK: - Masks

    /// A coverage mask (premultiplied black, alpha = coverage) of the artwork's silhouette at
    /// `side` px. The baked drop shadow is excluded: only pixels the folder body actually owns
    /// are covered, so overlays clipped with this never bleed into the shadow.
    func silhouetteCoverage(side: Int) -> CGImage? {
        let side = max(1, side)
        lock.lock()
        if let hit = coverages[side] { lock.unlock(); return hit }
        lock.unlock()
        let source = image(side: side)
        guard var px = Self.rgbaBytes(of: source) else { return nil }
        for i in 0..<(source.width * source.height) {
            let o = i * 4
            let a = CGFloat(px[o + 3]) / 255
            // Ramp from the shadow's ceiling to fully opaque, keeping a soft one-pixel edge.
            let cov = clamp01((a - 0.5) / 0.4)
            px[o] = 0; px[o + 1] = 0; px[o + 2] = 0
            px[o + 3] = Self.byte(cov)
        }
        guard let made = Self.imageFromBytes(px, width: source.width, height: source.height) else { return nil }
        lock.lock(); coverages[side] = made; lock.unlock()
        return made
    }

    // MARK: - Pixel plumbing

    static func rgbaBytes(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        // Re-draw rather than trusting the provider's layout: guarantees premultipliedLast/sRGB.
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: Raster.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return Array(UnsafeBufferPointer(start: bytes, count: w * h * 4))
    }

    static func imageFromBytes(_ px: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard w > 0, h > 0, px.count >= w * h * 4 else { return nil }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: Raster.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue),
              let data = ctx.data else { return nil }
        px.withUnsafeBufferPointer { src in
            data.copyMemory(from: src.baseAddress!, byteCount: w * h * 4)
        }
        return ctx.makeImage()
    }

    static func byte(_ v: CGFloat) -> UInt8 {
        UInt8(min(255, max(0, (v * 255).rounded())))
    }
}

// MARK: - Colour maths (per-pixel, allocation free)

@inline(__always)
func unpremultiplied(_ px: [UInt8], _ o: Int, _ a: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    guard a > 0 else { return (0, 0, 0) }
    return (min(1, CGFloat(px[o]) / 255 / a),
            min(1, CGFloat(px[o + 1]) / 255 / a),
            min(1, CGFloat(px[o + 2]) / 255 / a))
}

@inline(__always)
func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

@inline(__always)
func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
    let t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

/// Shortest distance between two hues on the 0…1 wheel (0…0.5).
@inline(__always)
func hueDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let d = abs(a - b).truncatingRemainder(dividingBy: 1)
    return min(d, 1 - d)
}

/// 1 inside the folder's own hue band, falling smoothly to 0 outside it.
@inline(__always)
func bandWeight(_ distance: CGFloat) -> CGFloat {
    1 - smoothstep(0.10, 0.17, distance)
}

/// Moves `hue` a `fraction` of the way to `target` along the short way round the wheel.
@inline(__always)
func rotate(_ hue: CGFloat, toward target: CGFloat, by fraction: CGFloat) -> CGFloat {
    guard fraction > 0 else { return hue }
    var delta = target - hue
    if delta > 0.5 { delta -= 1 }
    if delta < -0.5 { delta += 1 }
    var out = hue + delta * clamp01(fraction)
    if out < 0 { out += 1 }
    if out >= 1 { out -= 1 }
    return out
}

@inline(__always)
func rgbToHSB(r: CGFloat, g: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
    let delta = maxC - minC
    var hue: CGFloat = 0
    if delta > 0 {
        if maxC == r {
            hue = (g - b) / delta
            if hue < 0 { hue += 6 }
        } else if maxC == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue /= 6
    }
    let sat = maxC > 0 ? delta / maxC : 0
    return (hue, sat, maxC)
}

@inline(__always)
func hsbToRGB(h: CGFloat, s: CGFloat, v: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    guard s > 0 else { return (v, v, v) }
    let hh = (h - h.rounded(.down)) * 6
    let i = Int(hh)
    let f = hh - CGFloat(i)
    let p = v * (1 - s)
    let q = v * (1 - s * f)
    let t = v * (1 - s * (1 - f))
    switch i {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}
