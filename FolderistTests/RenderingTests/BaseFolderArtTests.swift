import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

/// The bitmap base-folder pipeline.
///
/// The artwork under test is a scratch copy of `$FOLDERIST_REFERENCE_ICON` (see
/// `RenderFixtures.baseFolderDirectory`) — nothing is committed to the repo. Every test here
/// skips cleanly when that environment variable is unset, and the vector suites keep covering
/// the fallback path.
@Suite("Base folder artwork", .serialized)
struct BaseFolderArtTests {

    private func art() throws -> BaseFolderArt? {
        RenderFixtures.baseArt
    }

    /// A colour as the Swift literal that would go into `StyleColor.folderBlue`.
    static func literal(_ c: StyleColor) -> String {
        let f = { (v: Double) in String(format: "%.4f", v) }
        return "StyleColor(red: \(f(c.red)), green: \(f(c.green)), blue: \(f(c.blue)))"
    }

    private func render(_ style: Style, canvas: CGFloat, resources: RenderResources) throws -> Bitmap {
        try #require(Bitmap(FolderIconRenderer.renderIcon(style: style, canvas: canvas, resources: resources)))
    }

    // MARK: - Loading and measurement

    @Test("artwork loads from a directory and reports the measured base colour")
    func loadsAndMeasures() throws {
        guard let art = try art() else { return }
        #expect(art.masterSize == 1024)
        let layout = art.layout
        let dominant = art.dominantColor()

        // Printed so the base colour can be lifted straight into `StyleColor.folderBlue`.
        print("""

        === Base folder artwork ==========================================
        source        : \(art.source.description)
        master size   : \(art.masterSize) px
        bounds        : \(layout.bounds)
        front top     : \(layout.frontTop) (measured: \(layout.frontTopMeasured))
        dominant HSB  : h \(layout.hue), s \(layout.saturation), b \(layout.brightness)
        dominantColor : \(Self.literal(dominant))
        ==================================================================

        """)

        // The artwork is a folder: it fills most of the canvas, leaves a margin, and has a
        // front panel that starts in the upper third and runs to the bottom.
        #expect(layout.bounds.width > 0.85 && layout.bounds.width < 1.0)
        #expect(layout.bounds.minY > 0.05 && layout.bounds.minY < 0.30)
        #expect(layout.frontTopMeasured, "the front panel's top edge should be measurable")
        #expect(layout.frontTop > layout.bounds.minY && layout.frontTop < layout.bounds.midY)
        #expect(layout.saturation > 0.05, "the artwork should carry a colour to remap")
    }

    @Test("the system folder icon loads at runtime")
    func systemIconLoads() throws {
        guard let system = BaseFolderArt.system() else {
            Issue.record("no system folder icon available on this machine")
            return
        }
        let dominant = system.dominantColor()
        let hsb = "h \(system.layout.hue), s \(system.layout.saturation), b \(system.layout.brightness)"
        print("""

        === System folder icon ===========================================
        source        : \(system.source.description)
        master size   : \(system.masterSize) px
        sizes         : \(system.availableSides.sorted())
        front top     : \(system.layout.frontTop) (measured: \(system.layout.frontTopMeasured))
        dominant HSB  : \(hsb)
        dominantColor : \(Self.literal(dominant))
        ==================================================================

        """)
        #expect(system.masterSize >= 512)
        #expect(system.source.isSystem)
        // Apple's folder is blue: hue somewhere in the cyan/blue arc.
        #expect(system.layout.hue > 0.45 && system.layout.hue < 0.70)
    }

    @Test("the alternate artwork loads under its own name, and user artwork wins over the system")
    func alternateArtworkAndPriority() throws {
        guard let dir = RenderFixtures.baseFolderDirectory else { return }
        // `BaseFolder-empty.png` is only found when asked for by name.
        let alternate = dir.appendingPathComponent("\(BaseFolderArt.alternateName).png")
        try? FileManager.default.removeItem(at: alternate)
        try FileManager.default.copyItem(at: dir.appendingPathComponent("BaseFolder.png"), to: alternate)
        defer { try? FileManager.default.removeItem(at: alternate) }
        BaseFolderArt.clearCaches()

        #expect(BaseFolderArt.load(directory: dir, name: BaseFolderArt.alternateName) != nil)
        #expect(BaseFolderArt.load(directory: dir, name: "NoSuchArtwork") == nil)

        // The user's file beats the system icon; the system icon only steps in without one.
        let user = try #require(BaseFolderArt.shared(roots: [dir], allowingSystemFallback: true))
        #expect(!user.source.isSystem)
        let empty = RenderFixtures.workDirectory.appendingPathComponent("no-base-folder-here")
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(BaseFolderArt.shared(roots: [empty], allowingSystemFallback: false) == nil)
        if BaseFolderArt.system() != nil {
            let fallback = try #require(BaseFolderArt.shared(roots: [empty], allowingSystemFallback: true))
            #expect(fallback.source.isSystem)
        }
    }

    @Test("a directory with no artwork falls back to the vector pipeline")
    func missingArtworkFallsBack() throws {
        let empty = RenderFixtures.workDirectory.appendingPathComponent("no-base-folder-here")
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let resources = DirectoryRenderResources(baseURL: empty, baseFolderDirectory: empty)
        #expect(resources.baseFolderArt == nil)
        let base = FolderBase(canvas: 256, resources: resources)
        #expect(!base.usesBitmap)
        // And it still renders a folder.
        let bitmap = try render(Style(name: "Fallback", fill: .solid(.folderBlue)),
                                canvas: 256, resources: resources)
        #expect(bitmap.opaquePixelCount > 256 * 256 / 4)
    }

    // MARK: - The default style is the artwork, untouched

    @Test("the default fill emits the artwork byte for byte")
    func defaultFillIsUntouched() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        let side = art.masterSize
        let style = Style(name: "Default", fill: .solid(.folderBlue))
        let image = FolderIconRenderer.renderIcon(style: style, canvas: CGFloat(side), resources: resources)
        let rendered = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let renderedBytes = try #require(BaseFolderArt.rgbaBytes(of: rendered))
        let artworkBytes = try #require(BaseFolderArt.rgbaBytes(of: art.image(side: side)))
        #expect(renderedBytes.count == artworkBytes.count)
        var worst = 0, differing = 0
        for i in 0..<min(renderedBytes.count, artworkBytes.count) {
            let d = abs(Int(renderedBytes[i]) - Int(artworkBytes[i]))
            if d > 0 { differing += 1; worst = max(worst, d) }
        }
        #expect(differing == 0,
                "the default style must copy the artwork: \(differing) bytes differ, worst by \(worst)")

        // …and the artwork itself is the file on disk, not a re-render of it.
        let sourceImage = try #require(NSImage(contentsOf: art.sourceURL ?? URL(fileURLWithPath: "/")))
        let sourceCG = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sourceBytes = try #require(BaseFolderArt.rgbaBytes(of: sourceCG))
        var sourceWorst = 0
        for i in 0..<min(renderedBytes.count, sourceBytes.count) {
            sourceWorst = max(sourceWorst, abs(Int(renderedBytes[i]) - Int(sourceBytes[i])))
        }
        #expect(sourceWorst <= 1, "the render drifted from the source file by \(sourceWorst)/255")
    }

    @Test("retuning the default sentinel never moves the vector fallback's palette")
    func vectorFallbackIsIndependentOfTheSentinel() throws {
        // The vector base folder is drawn with the colour its shading model was fitted with, so
        // the palette holds even when `StyleColor.folderBlue` is retuned to new artwork.
        let vector = DirectoryRenderResources(
            baseURL: RenderFixtures.workDirectory,
            baseFolderDirectory: RenderFixtures.workDirectory.appendingPathComponent("no-such-dir"))
        let base = FolderBase(canvas: 256, resources: vector)
        #expect(!base.usesBitmap)
        let fitted = FolderIconRenderer.Shading.fittedBase
        let probe = CGPoint(x: base.frontPanel.midX, y: base.frontPanel.midY)
        let asDefault = base.color(of: .solid(.folderBlue), at: probe)
        let asFitted = base.color(of: .solid(fitted), at: probe)
        #expect(asDefault.rgba == asFitted.rgba)
        // An ordinary colour is still taken at face value.
        let red = base.color(of: .solid(RenderFixtures.red), at: probe)
        #expect(red.rgba.r > red.rgba.b)
    }

    @Test("the default fill is detected within an epsilon, and only there")
    func defaultFillDetection() throws {
        let d = StyleColor.folderBlue
        #expect(BaseFolderArt.isDefaultFill(.solid(d)))
        let nudged = StyleColor(red: d.red + BaseFolderArt.defaultFillEpsilon / 2,
                                green: d.green, blue: d.blue)
        #expect(BaseFolderArt.isDefaultFill(.solid(nudged)))
        let off = StyleColor(red: d.red + 0.05, green: d.green, blue: d.blue)
        #expect(!BaseFolderArt.isDefaultFill(.solid(off)))
        #expect(!BaseFolderArt.isDefaultFill(.gradient(d, d, angleDegrees: 0)))
    }

    @Test("the default style renders the artwork at every icon-set size")
    func defaultAtEverySize() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        for size in FolderIconRenderer.iconSetSizes {
            let bitmap = try render(Style(name: "Default", fill: .solid(.folderBlue)),
                                    canvas: CGFloat(size), resources: resources)
            let expected = try #require(Bitmap(art.image(side: size)))
            #expect(bitmap.differenceFraction(from: expected, tolerance: 0.004) == 0,
                    "size \(size) is not the artwork")
        }
    }

    // MARK: - Recolouring

    @Test("recolouring never touches the alpha channel")
    func recolourPreservesAlpha() throws {
        guard let resources = RenderFixtures.bitmapResources() else { return }
        let plain = try render(Style(name: "Default", fill: .solid(.folderBlue)),
                               canvas: 512, resources: resources)
        for fill in [FolderFill.solid(RenderFixtures.red),
                     .solid(RenderFixtures.graphite),
                     .gradient(RenderFixtures.purple, RenderFixtures.orange, angleDegrees: 115)] {
            let recoloured = try render(Style(name: "R", fill: fill), canvas: 512, resources: resources)
            #expect(recoloured.maxAlphaDifference(from: plain) == 0,
                    "\(fill) changed the silhouette or the drop shadow")
        }
    }

    @Test("a recoloured folder takes on the target hue")
    func recolourReachesTargetHue() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        let targets: [(String, StyleColor)] = [
            ("red", RenderFixtures.red), ("green", RenderFixtures.green),
            ("purple", RenderFixtures.purple), ("orange", RenderFixtures.orange)
        ]
        for (name, colour) in targets {
            let image = FolderIconRenderer.renderIcon(style: Style(name: name, fill: .solid(colour)),
                                                      canvas: 512, resources: resources)
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let measured = BaseFolderArt.measure(cg)
            let target = rgbToHSB(r: CGFloat(colour.red), g: CGFloat(colour.green), b: CGFloat(colour.blue))
            #expect(hueDistance(measured.hue, target.0) < 0.03,
                    "\(name): folder hue \(measured.hue) vs target \(target.0)")
            // The base hue must be gone.
            #expect(hueDistance(measured.hue, art.layout.hue) > 0.05,
                    "\(name): the folder kept its original hue")
        }
    }

    @Test("low-saturation pixels stay neutral through a recolour")
    func lowSaturationPixelsStayNeutral() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        let side = 512
        let plain = try #require(Bitmap(art.image(side: side)))
        let recoloured = try render(Style(name: "Red", fill: .solid(RenderFixtures.red)),
                                    canvas: CGFloat(side), resources: resources)

        var checked = 0, worstSaturation: Float = 0, worstBrightnessDrift: Float = 0
        for y in 0..<side {
            for x in 0..<side {
                // The drop shadow counts too: it is the other thing that must stay neutral.
                guard plain.pixel(x: x, y: y).a > 0.10 else { continue }
                let hsbBefore = plain.hsb(x: x, y: y)
                guard hsbBefore.s < 0.10 else { continue }
                let hsbAfter = recoloured.hsb(x: x, y: y)
                checked += 1
                worstSaturation = max(worstSaturation, hsbAfter.s)
                worstBrightnessDrift = max(worstBrightnessDrift, abs(hsbAfter.b - hsbBefore.b))
            }
        }
        print("low-saturation pixels checked: \(checked), worst saturation after recolour: \(worstSaturation)")
        #expect(checked > 0, "the artwork has no low-saturation pixels to protect")
        #expect(worstSaturation < 0.14,
                "a neutral pixel picked up \(worstSaturation) saturation from the recolour")
        #expect(worstBrightnessDrift < 0.06,
                "a neutral pixel shifted brightness by \(worstBrightnessDrift)")
    }

    /// Synthetic artwork: a shaded blue panel with a white "paper" block and a grey band, so the
    /// paper guarantee is tested against artwork that definitely has paper in it. (The macOS
    /// folder used as reference artwork is solid blue — it has no white peek to check.)
    private static let paperArtworkDirectory: URL = {
        let dir = RenderFixtures.workDirectory.appendingPathComponent("PaperBase")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let side = 256
        if let cg = Raster.image(pixelWidth: side, pixelHeight: side, { ctx in
            let body = CGRect(x: 20, y: 40, width: 216, height: 180)
            // Shaded blue body, so there is per-pixel brightness variation to preserve.
            ctx.saveGState()
            ctx.addRect(body)
            ctx.clip()
            let blue = NSColor(srgbRed: 0.42, green: 0.81, blue: 0.99, alpha: 1)
            FolderIconRenderer.drawVerticalGradient(
                colors: [blue, blue.scalingBrightness(0.80)], locations: [0, 1], in: body, ctx: ctx)
            ctx.restoreGState()
            // The paper peek: near-white, faintly blue, exactly what must survive a recolour.
            ctx.setFillColor(NSColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 60, y: 60, width: 136, height: 40))
            // A neutral grey band, the other low-saturation case.
            ctx.setFillColor(NSColor(white: 0.55, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 60, y: 190, width: 136, height: 16))
        }) {
            RenderFixtures.writePNG(cg, to: dir.appendingPathComponent("BaseFolder.png"))
        }
        BaseFolderArt.clearCaches()
        return dir
    }()

    @Test("a white paper peek survives a recolour as white")
    func paperStaysWhite() throws {
        let dir = Self.paperArtworkDirectory
        let art = try #require(BaseFolderArt.load(directory: dir))
        let side = 256
        let plain = try #require(Bitmap(art.image(side: side)))
        let recoloured = try #require(Bitmap(BaseFolderArt.recolour(art.image(side: side),
                                                                    fill: .solid(RenderFixtures.red),
                                                                    base: art.layout).image))
        // Paper: still white, still barely saturated.
        for (x, y) in [(80, 70), (128, 80), (180, 95)] {
            let before = plain.hsb(x: x, y: y), after = recoloured.hsb(x: x, y: y)
            #expect(before.s < 0.05 && before.b > 0.95, "fixture check at (\(x), \(y))")
            #expect(after.s < 0.06, "paper at (\(x), \(y)) picked up \(after.s) saturation")
            #expect(after.b > 0.93, "paper at (\(x), \(y)) darkened to \(after.b)")
        }
        // Neutral grey: unchanged.
        let greyBefore = plain.pixel(x: 128, y: 198), greyAfter = recoloured.pixel(x: 128, y: 198)
        #expect(abs(greyBefore.r - greyAfter.r) < 0.03 && abs(greyBefore.b - greyAfter.b) < 0.03)
        // Body: recoloured, and still shaded top-to-bottom.
        let top = recoloured.hsb(x: 40, y: 50), bottom = recoloured.hsb(x: 40, y: 210)
        #expect(top.h < 0.10 || top.h > 0.95, "the body did not take the target hue, got \(top.h)")
        #expect(top.b > bottom.b + 0.05, "the body's shading was flattened")
    }

    @Test("recolouring keeps the artwork's shading, folds and texture")
    func recolourPreservesTexture() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        let side = 512
        let plain = try #require(Bitmap(art.image(side: side)))
        let recoloured = try render(Style(name: "Green", fill: .solid(RenderFixtures.green)),
                                    canvas: CGFloat(side), resources: resources)

        // A recolour is a *scale* of brightness, so every coloured pixel's brightness must come
        // out multiplied by the same factor. A tight distribution of that ratio is exactly what
        // "the folds, the shading and the texture survived" means, pixel by pixel.
        var ratios: [Double] = []
        for y in stride(from: 0, to: side, by: 2) {
            for x in stride(from: 0, to: side, by: 2) {
                guard plain.pixel(x: x, y: y).a > 0.99 else { continue }
                let before = plain.hsb(x: x, y: y)
                guard before.s > 0.30, before.b > 0.05 else { continue }
                ratios.append(Double(recoloured.hsb(x: x, y: y).b / before.b))
            }
        }
        #expect(ratios.count > 1000)
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        let deviation = (ratios.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(ratios.count)).squareRoot()
        let expected = Double(RenderFixtures.green.green) / Double(art.layout.brightness)
        #expect(abs(mean - expected) < 0.02,
                "brightness was scaled by \(mean), expected \(expected)")
        #expect(deviation < 0.02,
                "the brightness scale wobbled by \(deviation) — the shading was not preserved")

        // And the artwork's own variation is still there afterwards: the panel is not flat.
        let panel = FolderBase(canvas: CGFloat(side), resources: resources).frontPanel
        let high = recoloured.hsb(x: Int(panel.midX), y: Int(panel.minY + panel.height * 0.1)).b
        let low = recoloured.hsb(x: Int(panel.midX), y: Int(panel.maxY - panel.height * 0.02)).b
        #expect(abs(high - low) > 0.02, "the front panel came out flat")
    }

    @Test("a gradient fill varies the target colour along its axis")
    func gradientRecolourVariesAlongTheAxis() throws {
        guard let resources = RenderFixtures.bitmapResources() else { return }
        let side: CGFloat = 512
        let horizontal = try render(Style(name: "G", fill: .gradient(RenderFixtures.purple,
                                                                    RenderFixtures.orange,
                                                                    angleDegrees: 0)),
                                    canvas: side, resources: resources)
        let base = FolderBase(canvas: side, resources: resources)
        let panel = base.frontPanel
        let y = Int(panel.midY)
        let left = horizontal.hsb(x: Int(panel.minX + panel.width * 0.08), y: y)
        let right = horizontal.hsb(x: Int(panel.maxX - panel.width * 0.08), y: y)
        let purple = rgbToHSB(r: CGFloat(RenderFixtures.purple.red),
                              g: CGFloat(RenderFixtures.purple.green),
                              b: CGFloat(RenderFixtures.purple.blue))
        let orange = rgbToHSB(r: CGFloat(RenderFixtures.orange.red),
                              g: CGFloat(RenderFixtures.orange.green),
                              b: CGFloat(RenderFixtures.orange.blue))
        #expect(hueDistance(CGFloat(left.h), purple.0) < 0.05,
                "left edge hue \(left.h) should be purple \(purple.0)")
        #expect(hueDistance(CGFloat(right.h), orange.0) < 0.05,
                "right edge hue \(right.h) should be orange \(orange.0)")

        // The angle has to matter.
        let vertical = try render(Style(name: "G90", fill: .gradient(RenderFixtures.purple,
                                                                     RenderFixtures.orange,
                                                                     angleDegrees: 90)),
                                  canvas: side, resources: resources)
        #expect(vertical.differenceFraction(from: horizontal) > 0.20)
    }

    @Test("recolouring to the artwork's own dominant colour is close to a no-op")
    func recolourToDominantIsIdentity() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        let side = 512
        let plain = try #require(Bitmap(art.image(side: side)))
        let round = try render(Style(name: "Same", fill: .solid(art.dominantColor())),
                               canvas: CGFloat(side), resources: resources)
        #expect(round.differenceFraction(from: plain, tolerance: 0.05) < 0.02,
                "remapping onto the measured base colour should barely move a pixel")
    }

    // MARK: - Layout off the bitmap

    @Test("overlay layout and auto-fit follow the bitmap's own front panel")
    func layoutComesFromTheBitmap() throws {
        guard let resources = RenderFixtures.bitmapResources() else { return }
        let canvas: CGFloat = 512
        let base = FolderBase(canvas: canvas, resources: resources)
        #expect(base.usesBitmap)

        let panel = base.frontPanel
        #expect(panel.minY > base.bounds.minY && panel.maxY <= base.bounds.maxY + 0.5)
        for box in [FolderIconRenderer.graphicBox(base: base, withText: false),
                    FolderIconRenderer.graphicBox(base: base, withText: true),
                    FolderIconRenderer.textBox(base: base, withGraphic: false),
                    FolderIconRenderer.textBox(base: base, withGraphic: true)] {
            #expect(box.minX >= base.bounds.minX - 0.5 && box.maxX <= base.bounds.maxX + 0.5)
            #expect(box.minY >= panel.minY - 0.5 && box.maxY <= panel.maxY + 0.5)
        }

        // Auto-fit measures against that same panel.
        var style = Style(name: "T", fill: .solid(.folderBlue))
        style.text = TextOverlay(text: "ARCHIVE")
        let metrics = try #require(FolderIconRenderer.textMetrics(for: style, canvas: canvas, base: base))
        #expect(metrics.didAutoFit)
        #expect(metrics.size.width <= metrics.limit.width + 0.5)
        #expect(metrics.size.height <= metrics.limit.height + 0.5)
        #expect(metrics.panel == panel)
    }

    @Test("an engraved overlay samples the recoloured artwork underneath it")
    func embossSamplesTheArtwork() throws {
        guard let resources = RenderFixtures.bitmapResources() else { return }
        let canvas: CGFloat = 512
        let base = FolderBase(canvas: canvas, resources: resources)
        let panel = base.frontPanel
        let probe = CGPoint(x: panel.midX, y: panel.midY)

        // Sampled colour tracks the fill…
        let blue = base.color(of: .solid(.folderBlue), at: probe)
        let red = base.color(of: .solid(RenderFixtures.red), at: probe)
        #expect(blue.rgba.b > blue.rgba.r)
        #expect(red.rgba.r > red.rgba.b)
        // …and it is a *sample*, not the flat fill: the artwork is shaded, so probing two points
        // on the folder answers with two different colours.
        let tab = base.color(of: .solid(RenderFixtures.red),
                             at: CGPoint(x: panel.midX, y: base.bounds.minY + panel.height * 0.05))
        let low = base.color(of: .solid(RenderFixtures.red),
                             at: CGPoint(x: panel.midX, y: panel.maxY - panel.height * 0.02))
        #expect(abs(tab.luminance - low.luminance) > 0.02,
                "the probe returned a flat colour: tab \(tab.luminance) vs bottom \(low.luminance)")

        // Outside the folder there is nothing to sample; the fill answers instead.
        let outside = base.color(of: .solid(RenderFixtures.red), at: CGPoint(x: 2, y: 2))
        #expect(outside.rgba.r > 0.5)

        // The engraved glyph must actually land on the panel.
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.red)),
                               canvas: canvas, resources: resources)
        let engraved = try render(Style(name: "Engraved", fill: .solid(RenderFixtures.red),
                                        graphic: .sfSymbol(name: "star.fill")),
                                  canvas: canvas, resources: resources)
        #expect(engraved.differenceFraction(from: plain) > 0.01)
        #expect(engraved.maxAlphaDifference(from: plain) < 0.05)
    }

    // MARK: - Sample renders

    @Test("writes the bitmap-base sample renders")
    func writeBitmapSamples() throws {
        guard let art = try art(), let resources = RenderFixtures.bitmapResources() else { return }
        let dir = RenderFixtures.sampleDirectory.appendingPathComponent("base-folder")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // What the shipping app renders with no artwork installed: the system folder icon.
        if let system = BaseFolderArt.system() {
            let systemResources = DirectoryRenderResources(
                baseURL: RenderFixtures.assetsDirectory ?? RenderFixtures.workDirectory,
                userImagesDirectory: RenderFixtures.workDirectory,
                baseFolderDirectory: RenderFixtures.workDirectory.appendingPathComponent("no-such-dir"),
                preferSystemBaseFolder: true)
            RenderFixtures.writePNG(system.image(side: 512),
                                    to: dir.appendingPathComponent("00-system-icon.png"))
            for (name, style) in [("10-system-default", Style(name: "System", fill: .solid(.folderBlue))),
                                  ("11-system-red", Style(name: "System red",
                                                          fill: .solid(RenderFixtures.red)))] {
                let image = FolderIconRenderer.renderIcon(style: style, canvas: 512, resources: systemResources)
                RenderFixtures.writePNG(image, to: dir.appendingPathComponent("\(name).png"))
            }
        }

        var samples: [(String, Style)] = [
            ("01-default-bitmap", Style(name: "Default", fill: .solid(.folderBlue))),
            ("02-recolour-red", Style(name: "Red", fill: .solid(RenderFixtures.red))),
            ("03-recolour-green", Style(name: "Green", fill: .solid(RenderFixtures.green))),
            ("04-recolour-graphite", Style(name: "Graphite", fill: .solid(RenderFixtures.graphite))),
            ("05-recolour-gradient", Style(name: "Gradient",
                                           fill: .gradient(RenderFixtures.purple, RenderFixtures.orange,
                                                           angleDegrees: 115))),
            ("06-symbol-on-bitmap", Style(name: "Symbol", fill: .solid(RenderFixtures.red),
                                          graphic: .sfSymbol(name: "music.note"))),
            ("07-text-on-bitmap", Style(name: "Text", fill: .solid(RenderFixtures.green),
                                        text: TextOverlay(text: "2026"))),
            ("08-stamp-on-bitmap", Style(name: "Stamp", fill: .solid(RenderFixtures.orange),
                                         graphic: .image(fileName: RenderFixtures.stampFileName,
                                                         mode: .stamp)))
        ]
        var oversized = Style(name: "Stamp clip", fill: .solid(RenderFixtures.orange),
                              graphic: .image(fileName: RenderFixtures.stampFileName, mode: .stamp))
        oversized.graphicTransform.scale = 4
        samples.append(("09-stamp-clip-demo", oversized))
        samples.append(("12-image-fill", Style(name: "Fill", fill: .solid(.folderBlue),
                                               graphic: .image(fileName: RenderFixtures.photoFileName,
                                                               mode: .fill))))
        var zoomedOver = Style(name: "Over", fill: .solid(.folderBlue),
                               graphic: .image(fileName: RenderFixtures.photoFileName, mode: .over))
        zoomedOver.graphicTransform.scale = 2.6
        samples.append(("13-image-over-zoomed", zoomedOver))

        for (name, style) in samples {
            let image = FolderIconRenderer.renderIcon(style: style, canvas: 512, resources: resources)
            RenderFixtures.writePNG(image, to: dir.appendingPathComponent("\(name).png"))
        }
        RenderFixtures.writePNG(art.image(side: 512), to: dir.appendingPathComponent("00-artwork.png"))
        print("Base-folder samples written to: \(dir.path)")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("01-default-bitmap.png").path))
    }
}

// MARK: - Stamp clipping (issue #5)

/// `.stamp` used to paint wherever the transform put it; like `.over`, it must be cropped to the
/// folder. Both pipelines are checked, because they crop with different machinery.
@Suite("Image stamp mode", .serialized)
struct ImageStampClippingTests {

    private func render(_ style: Style, canvas: CGFloat, resources: RenderResources) throws -> Bitmap {
        try #require(Bitmap(FolderIconRenderer.renderIcon(style: style, canvas: canvas, resources: resources)))
    }

    private func providers() -> [(String, RenderResources)] {
        var out: [(String, RenderResources)] = [
            ("vector", RenderFixtures.resources(userImages: RenderFixtures.workDirectory))
        ]
        if let bitmap = RenderFixtures.bitmapResources(userImages: RenderFixtures.workDirectory) {
            out.append(("bitmap", bitmap))
        }
        return out
    }

    @Test("an oversized stamp paints nothing outside the folder", arguments: [
        (3.0, 0.0, 0.0), (4.0, 0.2, -0.2), (2.5, -0.3, 0.25), (8.0, 0.0, 0.0)
    ])
    func stampIsClippedToTheSilhouette(scale: Double, dx: Double, dy: Double) throws {
        for (label, resources) in providers() {
            let canvas: CGFloat = 512
            let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.orange)),
                                   canvas: canvas, resources: resources)
            var style = Style(name: "Stamp", fill: .solid(RenderFixtures.orange),
                              graphic: .image(fileName: RenderFixtures.stampFileName, mode: .stamp))
            style.graphicTransform.scale = scale
            style.graphicTransform.offsetX = dx
            style.graphicTransform.offsetY = dy
            let stamped = try render(style, canvas: canvas, resources: resources)

            let escaped = stamped.opaquePixelsOutside(plain)
            #expect(escaped == 0,
                    "\(label): scale \(scale) offset (\(dx), \(dy)) stamped \(escaped) px outside the folder")
            #expect(stamped.maxAlphaDifference(from: plain) < 0.03,
                    "\(label): the stamp changed the icon's silhouette")
            // The corners of the canvas are the loudest witness.
            for (fx, fy) in [(0.01, 0.01), (0.99, 0.01), (0.01, 0.99), (0.99, 0.99)] {
                #expect(stamped.pixel(fx: fx, fy: fy).a < 0.01, "\(label): corner (\(fx), \(fy)) painted")
            }
            // …and the part that does fit is still engraved. (Past a certain zoom the visible
            // crop is the stamp's own white centre, which engraves nothing by design.)
            if scale <= 4 {
                #expect(stamped.differenceFraction(from: plain) > 0.05,
                        "\(label): the stamp disappeared entirely")
            }
        }
    }

    @Test("a rotated oversized stamp stays inside the folder")
    func rotatedStampStaysClipped() throws {
        for (label, resources) in providers() {
            let canvas: CGFloat = 512
            let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.orange)),
                                   canvas: canvas, resources: resources)
            var style = Style(name: "Stamp", fill: .solid(RenderFixtures.orange),
                              graphic: .image(fileName: RenderFixtures.stampFileName, mode: .stamp))
            style.graphicTransform.scale = 3.5
            style.graphicTransform.rotationDegrees = 30
            let stamped = try render(style, canvas: canvas, resources: resources)
            #expect(stamped.opaquePixelsOutside(plain) == 0, "\(label): rotated stamp escaped the folder")
        }
    }

    @Test("fill and over stay inside the bitmap folder too", arguments: [ImageMode.fill, .over])
    func bitmapModesStayInsideTheFolder(mode: ImageMode) throws {
        guard let resources = RenderFixtures.bitmapResources(userImages: RenderFixtures.workDirectory)
        else { return }
        let canvas: CGFloat = 512
        let plain = try render(Style(name: "Plain", fill: .solid(.folderBlue)),
                               canvas: canvas, resources: resources)
        var style = Style(name: mode.rawValue, fill: .solid(.folderBlue),
                          graphic: .image(fileName: RenderFixtures.photoFileName, mode: mode))
        style.graphicTransform.scale = 2.4
        style.graphicTransform.offsetX = -0.15
        let bitmap = try render(style, canvas: canvas, resources: resources)

        #expect(bitmap.opaquePixelsOutside(plain) == 0, "\(mode) painted outside the folder")
        #expect(bitmap.maxAlphaDifference(from: plain) < 0.03, "\(mode) changed the silhouette")
        #expect(bitmap.differenceFraction(from: plain) > 0.10, "\(mode) drew nothing")
        if mode == .fill {
            // The tab is above the front panel, so it keeps the folder's own colour.
            let base = FolderBase(canvas: canvas, resources: resources)
            let tab = bitmap.pixel(x: Int(base.bounds.minX + base.width * 0.12),
                                   y: Int((base.bounds.minY + base.frontPanel.minY) / 2))
            #expect(tab.a > 0.9 && tab.b > tab.r, "the tab lost the folder colour, got \(tab)")
        }
    }

    @Test("clipping leaves a stamp that already fits untouched")
    func inBoundsStampIsUnaffected() throws {
        let resources = RenderFixtures.resources(userImages: RenderFixtures.workDirectory)
        let style = Style(name: "Stamp", fill: .solid(RenderFixtures.orange),
                          graphic: .image(fileName: RenderFixtures.stampFileName, mode: .stamp))
        let stamped = try render(style, canvas: 512, resources: resources)
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.orange)),
                               canvas: 512, resources: resources)
        // Still engraved, still inside, and the dark ring still reads darker than the folder.
        #expect(stamped.differenceFraction(from: plain) > 0.02)
        let geo = FolderGeometry(canvas: 512)
        let box = FolderIconRenderer.graphicBox(geo: geo, withText: false)
        let ring = stamped.pixel(x: Int(box.midX - box.width * 0.25), y: Int(box.midY))
        let untouched = plain.pixel(x: Int(box.midX - box.width * 0.25), y: Int(box.midY))
        #expect(ring.r + ring.g + ring.b < untouched.r + untouched.g + untouched.b)
    }
}
