import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

/// Writes a set of representative renders to disk so a human can eyeball the artwork.
///
/// Output directory: `$FOLDERIST_SAMPLE_DIR`, or `/private/tmp/folderist-render-samples`.
/// Run just this suite with:
///     FOLDERIST_SAMPLE_DIR=/tmp/samples swift test --filter "Sample renders"
@Suite("Sample renders", .serialized)
struct SampleRenderTests {

    @Test("writes eyeball-able sample PNGs")
    func writeSampleRenders() throws {
        let dir = RenderFixtures.sampleDirectory
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let photo = RenderFixtures.photoFileName
        let stamp = RenderFixtures.stampFileName
        let resources = RenderFixtures.resources(userImages: RenderFixtures.workDirectory)

        var samples: [(String, Style)] = []

        samples.append(("01-plain-blue", Style(name: "Plain", fill: .solid(RenderFixtures.blue))))
        samples.append(("02-plain-red", Style(name: "Red", fill: .solid(RenderFixtures.red))))
        samples.append(("03-plain-graphite", Style(name: "Graphite", fill: .solid(RenderFixtures.graphite))))
        samples.append(("04-gradient", Style(name: "Gradient",
                                             fill: .gradient(RenderFixtures.purple, RenderFixtures.orange,
                                                             angleDegrees: 115))))

        samples.append(("05-sfsymbol-emboss", Style(name: "Symbol",
                                                    fill: .solid(RenderFixtures.blue),
                                                    graphic: .sfSymbol(name: "music.note"))))

        var filled = OverlayEffects()
        filled.emboss = false
        filled.fill = true
        samples.append(("06-sfsymbol-fill", Style(name: "Symbol Fill",
                                                  fill: .solid(RenderFixtures.green),
                                                  graphic: .sfSymbol(name: "airplane"),
                                                  graphicEffects: filled)))

        var shadowed = OverlayEffects()
        shadowed.shadow = true
        shadowed.outerStroke = true
        samples.append(("07-sfsymbol-shadow-stroke", Style(name: "Symbol FX",
                                                           fill: .solid(RenderFixtures.orange),
                                                           graphic: .sfSymbol(name: "heart.fill"),
                                                           graphicEffects: shadowed)))

        if RenderFixtures.assetsDirectory != nil {
            samples.append(("08-bundled-symbol", Style(name: "Lucide",
                                                       fill: .solid(RenderFixtures.purple),
                                                       graphic: .bundledSymbol(catalog: "lucide", name: "camera"))))
        }

        samples.append(("09-emoji", Style(name: "Emoji",
                                          fill: .solid(RenderFixtures.blue),
                                          graphic: .emoji("🚀"))))

        var textOnly = TextOverlay(text: "2026")
        textOnly.fontFamily = "Helvetica Neue"
        textOnly.fontFace = "Bold"
        samples.append(("10-text-autofit", Style(name: "Text",
                                                 fill: .solid(RenderFixtures.green),
                                                 text: textOnly)))

        samples.append(("11-text-long", Style(name: "Text long",
                                              fill: .solid(RenderFixtures.red),
                                              text: TextOverlay(text: "ARCHIVE"))))

        samples.append(("12-symbol-and-text", Style(name: "Both",
                                                    fill: .solid(RenderFixtures.blue),
                                                    graphic: .sfSymbol(name: "briefcase.fill"),
                                                    text: TextOverlay(text: "Work"))))

        var rotated = OverlayTransform()
        rotated.rotationDegrees = -12
        rotated.scale = 1.15
        rotated.offsetY = -0.02
        samples.append(("13-transformed", Style(name: "Transformed",
                                                fill: .solid(RenderFixtures.purple),
                                                graphic: .sfSymbol(name: "star.fill"),
                                                graphicTransform: rotated)))

        samples.append(("14-image-fill", Style(name: "Image Fill",
                                               fill: .solid(RenderFixtures.blue),
                                               graphic: .image(fileName: photo, mode: .fill))))
        samples.append(("15-image-over", Style(name: "Image Over",
                                               fill: .solid(RenderFixtures.blue),
                                               graphic: .image(fileName: photo, mode: .over))))
        samples.append(("16-image-stamp", Style(name: "Image Stamp",
                                                fill: .solid(RenderFixtures.orange),
                                                graphic: .image(fileName: stamp, mode: .stamp))))
        samples.append(("17-image-only", Style(name: "Image Only",
                                               fill: .solid(RenderFixtures.blue),
                                               graphic: .image(fileName: photo, mode: .only))))

        var gradientTextStyle = Style(name: "Gradient + text",
                                      fill: .gradient(StyleColor(red: 0.20, green: 0.55, blue: 0.95),
                                                      StyleColor(red: 0.10, green: 0.22, blue: 0.50),
                                                      angleDegrees: 90))
        gradientTextStyle.text = TextOverlay(text: "A")
        samples.append(("18-gradient-text", gradientTextStyle))

        // "Over" mode is a crop tool: zoom past the folder, pan to pick the visible part.
        var zoomed = Style(name: "Over zoomed", fill: .solid(RenderFixtures.blue),
                           graphic: .image(fileName: photo, mode: .over))
        zoomed.graphicTransform.scale = 2.6
        samples.append(("19-image-over-zoomed", zoomed))
        var panned = zoomed
        panned.graphicTransform.offsetX = -0.16
        panned.graphicTransform.offsetY = 0.12
        samples.append(("20-image-over-panned", panned))

        // Asymmetric overlays, so an upside-down render is obvious at a glance.
        samples.append(("21-orientation-emoji", Style(name: "Up", fill: .solid(RenderFixtures.blue),
                                                      graphic: .emoji("⬆️"))))
        samples.append(("22-orientation-text", Style(name: "L", fill: .solid(RenderFixtures.green),
                                                     text: TextOverlay(text: "L"))))
        if RenderFixtures.assetsDirectory != nil {
            samples.append(("23-orientation-symbol",
                            Style(name: "Arrow", fill: .solid(RenderFixtures.purple),
                                  graphic: .bundledSymbol(catalog: "lucide", name: "arrow-up"))))
        }

        for (name, style) in samples {
            let image = FolderIconRenderer.renderIcon(style: style, canvas: 512, resources: resources)
            RenderFixtures.writePNG(image, to: dir.appendingPathComponent("\(name).png"))
        }

        // A size ladder for one style, plus two contact sheets.
        let ladderStyle = Style(name: "Ladder", fill: .solid(RenderFixtures.blue),
                                graphic: .sfSymbol(name: "gearshape.fill"))
        for (size, image) in FolderIconRenderer.renderIconSet(style: ladderStyle, resources: resources) {
            RenderFixtures.writePNG(image, to: dir.appendingPathComponent("sizes/\(String(format: "%04d", size)).png"))
        }
        writeContactSheet(styles: samples.map(\.1), resources: resources,
                          to: dir.appendingPathComponent("00-contact-sheet.png"))
        writeSmallSizeSheet(style: ladderStyle, resources: resources,
                            to: dir.appendingPathComponent("00-small-sizes.png"))
        writeReferenceComparison(to: dir.appendingPathComponent("00-vs-system-folder.png"))

        print("Folderist render samples written to: \(dir.path)")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("01-plain-blue.png").path))
    }

    /// Grid of every sample at 128 px on a neutral background.
    private func writeContactSheet(styles: [Style], resources: RenderResources, to url: URL) {
        let cell = 140, columns = 6
        let rows = Int(ceil(Double(styles.count) / Double(columns)))
        let w = cell * columns, h = cell * rows
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return }
        ctx.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for (i, style) in styles.enumerated() {
            let image = FolderIconRenderer.renderIcon(style: style, canvas: 128, resources: resources)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let col = i % columns, row = i / columns
            let x = col * cell + 6
            let y = h - (row + 1) * cell + 6
            ctx.draw(cg, in: CGRect(x: CGFloat(x), y: CGFloat(y), width: 128, height: 128))
        }
        if let cg = ctx.makeImage() { RenderFixtures.writePNG(cg, to: url) }
    }

    /// A default-blue folder at every icon-set size next to the system folder, for eyeballing
    /// the silhouette and palette. Skipped when `FOLDERIST_REFERENCE_ICON` isn't set.
    private func writeReferenceComparison(to url: URL) {
        guard let path = ProcessInfo.processInfo.environment["FOLDERIST_REFERENCE_ICON"],
              let reference = NSImage(contentsOfFile: path),
              let referenceCG = reference.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        let sizes = [512, 256, 128, 64, 32, 16]
        let cell = 280, w = cell * sizes.count, h = cell * 2 + 24
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return }
        ctx.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let style = Style(name: "Blue", fill: .solid(.folderBlue))
        for (i, size) in sizes.enumerated() {
            let box = CGFloat(cell - 24)
            let x = CGFloat(i * cell) + 12
            // Top row: the system folder. Bottom row: ours.
            ctx.draw(referenceCG, in: CGRect(x: x, y: CGFloat(h) - box - 12, width: box, height: box))
            let ours = FolderIconRenderer.renderIcon(style: style, canvas: CGFloat(size),
                                                     resources: EmptyRenderResources())
            if let cg = ours.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.interpolationQuality = size < 64 ? .none : .high
                ctx.draw(cg, in: CGRect(x: x, y: 12, width: box, height: box))
            }
        }
        if let cg = ctx.makeImage() { RenderFixtures.writePNG(cg, to: url) }
    }

    /// The small end of the ladder, drawn at 4×/2× nearest-neighbour zoom for inspection.
    private func writeSmallSizeSheet(style: Style, resources: RenderResources, to url: URL) {
        let sizes = [16, 32, 64, 128]
        let w = 4 * 128 + 40, h = 160
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return }
        ctx.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.interpolationQuality = .none
        var x = 8
        for size in sizes {
            let image = FolderIconRenderer.renderIcon(style: style, canvas: CGFloat(size), resources: resources)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let zoom = 128 / size
            let drawn = size * zoom
            ctx.draw(cg, in: CGRect(x: CGFloat(x), y: CGFloat(h - drawn - 16),
                                    width: CGFloat(drawn), height: CGFloat(drawn)))
            x += drawn + 8
        }
        if let cg = ctx.makeImage() { RenderFixtures.writePNG(cg, to: url) }
    }
}
