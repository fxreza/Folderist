import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

// MARK: - Pixel sampling helpers

/// A decoded RGBA bitmap of a rendered icon, for deterministic pixel assertions.
struct Bitmap {
    let width: Int
    let height: Int
    /// Straight (un-premultiplied) RGBA, 0…1.
    private let pixels: [Float]

    init?(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(cg)
    }

    init?(_ cg: CGImage) {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var out = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let a = Float(bytes[i * 4 + 3]) / 255
            if a > 0 {
                out[i * 4] = Float(bytes[i * 4]) / 255 / a
                out[i * 4 + 1] = Float(bytes[i * 4 + 1]) / 255 / a
                out[i * 4 + 2] = Float(bytes[i * 4 + 2]) / 255 / a
            }
            out[i * 4 + 3] = a
        }
        self.width = w
        self.height = h
        self.pixels = out
    }

    /// Pixel at top-left-origin coordinates.
    func pixel(x: Int, y: Int) -> (r: Float, g: Float, b: Float, a: Float) {
        let cx = min(width - 1, max(0, x)), cy = min(height - 1, max(0, y))
        let o = (cy * width + cx) * 4
        return (pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3])
    }

    /// Pixel addressed by fractions of the image size.
    func pixel(fx: Double, fy: Double) -> (r: Float, g: Float, b: Float, a: Float) {
        pixel(x: Int(Double(width) * fx), y: Int(Double(height) * fy))
    }

    var opaquePixelCount: Int {
        var n = 0
        for i in 0..<(width * height) where pixels[i * 4 + 3] > 0.5 { n += 1 }
        return n
    }

    /// Alpha-weighted average color over the whole image.
    var averageColor: (r: Float, g: Float, b: Float) {
        var r: Float = 0, g: Float = 0, b: Float = 0, wsum: Float = 0
        for i in 0..<(width * height) {
            let a = pixels[i * 4 + 3]
            guard a > 0 else { continue }
            r += pixels[i * 4] * a; g += pixels[i * 4 + 1] * a; b += pixels[i * 4 + 2] * a
            wsum += a
        }
        guard wsum > 0 else { return (0, 0, 0) }
        return (r / wsum, g / wsum, b / wsum)
    }

    var averageAlpha: Float {
        var a: Float = 0
        for i in 0..<(width * height) { a += pixels[i * 4 + 3] }
        return a / Float(width * height)
    }

    /// Alpha-weighted average colour of one row, over `x0...x1`.
    func averageRow(_ y: Int, from x0: Int, to x1: Int) -> (r: Float, g: Float, b: Float) {
        var r: Float = 0, g: Float = 0, b: Float = 0, n: Float = 0
        for x in x0...x1 {
            let p = pixel(x: x, y: y)
            r += p.r; g += p.g; b += p.b; n += 1
        }
        guard n > 0 else { return (0, 0, 0) }
        return (r / n, g / n, b / n)
    }

    // MARK: Sub-pixel silhouette edges (alpha 0.5 crossing, ignoring any soft shadow)

    private func edge(_ samples: [Float]) -> Double? {
        guard let solid = samples.firstIndex(where: { $0 > 0.9 }), solid > 0 else { return nil }
        var i = solid
        while i > 0 && samples[i - 1] > 0.5 { i -= 1 }
        let a1 = Double(samples[i]), a0 = i > 0 ? Double(samples[i - 1]) : 0
        guard a1 > a0 else { return Double(i) }
        return Double(i) - (a1 - 0.5) / (a1 - a0)
    }

    /// Leftmost opaque edge of row `y`, to sub-pixel accuracy.
    func leftEdge(row y: Int) -> Double? {
        edge((0..<width).map { pixel(x: $0, y: y).a })
    }

    /// Rightmost opaque edge of row `y`. Measured from the right, then mirrored back.
    func rightEdge(row y: Int) -> Double? {
        edge((0..<width).reversed().map { pixel(x: $0, y: y).a }).map { Double(width) - $0 }
    }

    /// Topmost opaque edge of column `x`.
    func topEdge(column x: Int) -> Double? {
        edge((0..<height).map { pixel(x: x, y: $0).a })
    }

    /// Bottommost opaque edge of column `x`.
    func bottomEdge(column x: Int) -> Double? {
        edge((0..<height).reversed().map { pixel(x: x, y: $0).a }).map { Double(height) - $0 }
    }

    /// Mean of `edge` over a range, ignoring rows/columns where it can't be measured.
    static func mean(_ values: [Double?]) -> Double? {
        let ok = values.compactMap { $0 }
        guard !ok.isEmpty else { return nil }
        return ok.reduce(0, +) / Double(ok.count)
    }

    /// Total alpha in the top half versus the bottom half — an orientation probe.
    var alphaHalves: (top: Double, bottom: Double) {
        var top = 0.0, bottom = 0.0
        for y in 0..<height {
            var row = 0.0
            for x in 0..<width { row += Double(pixel(x: x, y: y).a) }
            if y < height / 2 { top += row } else { bottom += row }
        }
        return (top, bottom)
    }

    /// Row centroid (as a fraction of the image height) of the pixels that differ from `other`,
    /// weighted by how much they differ. `nil` when nothing changed.
    func changeCentroidY(from other: Bitmap, tolerance: Float = 0.02) -> Double? {
        guard width == other.width, height == other.height else { return nil }
        var weighted = 0.0, total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let a = pixel(x: x, y: y), b = other.pixel(x: x, y: y)
                let d = max(abs(a.r - b.r), max(abs(a.g - b.g), max(abs(a.b - b.b), abs(a.a - b.a))))
                guard d > tolerance else { continue }
                weighted += Double(d) * Double(y)
                total += Double(d)
            }
        }
        guard total > 0 else { return nil }
        return weighted / total / Double(height)
    }

    /// Number of pixels that are opaque here while `other` is transparent — "ink outside the
    /// silhouette", when `other` is the plain folder.
    func opaquePixelsOutside(_ other: Bitmap, threshold: Float = 0.02) -> Int {
        guard width == other.width, height == other.height else { return width * height }
        var n = 0
        for i in 0..<(width * height)
        where pixels[i * 4 + 3] > threshold && other.pixels[i * 4 + 3] <= threshold { n += 1 }
        return n
    }

    /// Straight (un-premultiplied) HSB of a pixel.
    func hsb(x: Int, y: Int) -> (h: Float, s: Float, b: Float) {
        let p = pixel(x: x, y: y)
        let maxC = max(p.r, max(p.g, p.b)), minC = min(p.r, min(p.g, p.b))
        let delta = maxC - minC
        var h: Float = 0
        if delta > 0 {
            if maxC == p.r { h = (p.g - p.b) / delta; if h < 0 { h += 6 } }
            else if maxC == p.g { h = (p.b - p.r) / delta + 2 }
            else { h = (p.r - p.g) / delta + 4 }
            h /= 6
        }
        return (h, maxC > 0 ? delta / maxC : 0, maxC)
    }

    /// Largest per-channel alpha difference against `other`.
    func maxAlphaDifference(from other: Bitmap) -> Float {
        guard width == other.width, height == other.height else { return 1 }
        var worst: Float = 0
        for y in 0..<height {
            for x in 0..<width {
                worst = max(worst, abs(pixel(x: x, y: y).a - other.pixel(x: x, y: y).a))
            }
        }
        return worst
    }

    /// Fraction of pixels that differ from `other` by more than `tolerance` in any channel.
    func differenceFraction(from other: Bitmap, tolerance: Float = 0.02) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        var differing = 0
        for i in 0..<(width * height) {
            for c in 0..<4 where abs(pixels[i * 4 + c] - other.pixels[i * 4 + c]) > tolerance {
                differing += 1
                break
            }
        }
        return Double(differing) / Double(width * height)
    }
}

// MARK: - Fixtures

enum RenderFixtures {
    /// The repo's `Assets/` directory, if it can be located.
    static var assetsDirectory: URL? {
        if let env = ProcessInfo.processInfo.environment["FOLDERIST_ASSETS_DIR"] {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // …/FolderistTests/RenderingTests/RenderTestSupport.swift → repo root
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("Assets")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("icons").path) {
                return candidate
            }
        }
        return nil
    }

    /// The macOS system folder icon at 1024 px, used *only* as a measurement reference for the
    /// shape and palette tests. Nothing from it is ever copied into the app.
    ///
    /// Point `FOLDERIST_REFERENCE_ICON` at an extracted
    /// `GenericFolderIcon.iconset/icon_512x512@2x.png`. Tests that need it skip when it is
    /// missing, so a checkout without the reference still passes.
    static var referenceIcon: Bitmap? {
        guard let path = ProcessInfo.processInfo.environment["FOLDERIST_REFERENCE_ICON"],
              FileManager.default.fileExists(atPath: path),
              let image = NSImage(contentsOfFile: path),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return Bitmap(cg)
    }

    /// Scratch directory for generated test images, unique per test run.
    static let workDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderistRenderTests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Where eyeball-able sample renders are written.
    static var sampleDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["FOLDERIST_SAMPLE_DIR"] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: "/private/tmp/folderist-render-samples")
    }

    // MARK: Base folder artwork

    /// A scratch `BaseFolder` directory seeded with the reference artwork, so the bitmap
    /// pipeline can be exercised without committing Apple's icon into the repo.
    ///
    /// `nil` when `FOLDERIST_REFERENCE_ICON` is unset — every bitmap test skips in that case.
    static let baseFolderDirectory: URL? = {
        guard let path = ProcessInfo.processInfo.environment["FOLDERIST_REFERENCE_ICON"],
              FileManager.default.fileExists(atPath: path) else { return nil }
        let dir = workDirectory.appendingPathComponent("BaseFolder")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("BaseFolder.png")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: destination)
        BaseFolderArt.clearCaches()
        return FileManager.default.fileExists(atPath: destination.path) ? dir : nil
    }()

    /// The artwork under test.
    static var baseArt: BaseFolderArt? {
        guard let dir = baseFolderDirectory else { return nil }
        return BaseFolderArt.shared(roots: [dir])
    }

    /// Resources whose base folder is the scratch artwork rather than the vector fallback.
    static func bitmapResources(userImages: URL? = nil) -> RenderResources? {
        guard let dir = baseFolderDirectory else { return nil }
        return DirectoryRenderResources(baseURL: assetsDirectory ?? workDirectory,
                                        userImagesDirectory: userImages ?? workDirectory,
                                        baseFolderDirectory: dir)
    }

    static func resources(userImages: URL? = nil) -> RenderResources {
        if let assets = assetsDirectory {
            return DirectoryRenderResources(baseURL: assets, userImagesDirectory: userImages ?? workDirectory)
        }
        return DirectoryRenderResources(baseURL: userImages ?? workDirectory,
                                        userImagesDirectory: userImages ?? workDirectory)
    }

    /// Writes a PNG built by `draw` into the work directory and returns its file name.
    @discardableResult
    static func makeImageFile(named name: String, size: Int = 256,
                              _ draw: (CGContext) -> Void) -> String {
        let url = workDirectory.appendingPathComponent(name)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return name }
        draw(ctx)
        if let cg = ctx.makeImage() {
            writePNG(cg, to: url)
        }
        return name
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func writePNG(_ image: NSImage, to url: URL) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        writePNG(cg, to: url)
    }

    /// A colour "photo" stand-in: a diagonal gradient with a light disc.
    static let photoFileName: String = makeImageFile(named: "fixture-photo.png", size: 512) { ctx in
        let colors = [NSColor.systemPink.cgColor, NSColor.systemTeal.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 512, y: 512), options: [])
        }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: 150, y: 150, width: 212, height: 212))
    }

    /// A black-and-white stamp source: black ring + bar on white.
    static let stampFileName: String = makeImageFile(named: "fixture-stamp.png", size: 512) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: CGRect(x: 60, y: 60, width: 392, height: 392))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 150, y: 150, width: 212, height: 212))
        ctx.fill(CGRect(x: 236, y: 60, width: 40, height: 392))
    }

    /// A deliberately top-heavy probe: an opaque band across the **top** quarter, the rest clear.
    /// Any overlay path that renders this upside down puts the band at the bottom instead.
    /// (`makeImageFile` hands out a plain, y-up CG context, so the band goes at high y.)
    static let topBandFileName: String = makeImageFile(named: "fixture-top-band.png", size: 256) { ctx in
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 192, width: 256, height: 64))
    }

    /// The same probe as an `NSImage`, for the resource-provider stubs.
    static var topBandImage: NSImage? {
        NSImage(contentsOf: workDirectory.appendingPathComponent(topBandFileName))
    }

    /// A solid white square — the classic "nothing to engrave" stamp input.
    static let whiteSquareFileName: String = makeImageFile(named: "fixture-white-square.png", size: 256) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    }

    // Convenience colors.
    static let blue = StyleColor.folderBlue
    static let red = StyleColor(red: 0.94, green: 0.32, blue: 0.30)
    static let green = StyleColor(red: 0.36, green: 0.80, blue: 0.45)
    static let purple = StyleColor(red: 0.62, green: 0.44, blue: 0.92)
    static let orange = StyleColor(red: 0.98, green: 0.66, blue: 0.24)
    static let graphite = StyleColor(red: 0.42, green: 0.44, blue: 0.48)
}
