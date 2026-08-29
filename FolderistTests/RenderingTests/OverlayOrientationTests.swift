import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

/// Serves one deliberately **top-heavy** image for every overlay kind, so an upside-down
/// overlay is unmissable. The old test fixtures were all vertically symmetric, which is
/// exactly why the flip bug survived them.
private struct ProbeRenderResources: RenderResources {
    let probe: NSImage
    func symbolImage(catalog: String, name: String) -> NSImage? { probe }
    func userImage(named fileName: String) -> NSImage? { probe }
    func emojiImage(for emoji: String) -> NSImage? { probe }
}

@Suite("Overlay orientation", .serialized)
struct OverlayOrientationTests {

    private var probe: NSImage {
        get throws { try #require(RenderFixtures.topBandImage) }
    }

    private func render(_ style: Style, canvas: CGFloat = 512, resources: RenderResources) throws -> Bitmap {
        try #require(Bitmap(FolderIconRenderer.renderIcon(style: style, canvas: canvas, resources: resources)))
    }

    // MARK: - Primitives

    @Test("Raster.drawImage keeps an NSImage right-side-up in a top-left-origin context")
    func rasterDrawImageOrientation() throws {
        let image = try probe
        let drawn = try #require(Raster.image(pixelWidth: 200, pixelHeight: 400) { ctx in
            Raster.drawImage(image, in: CGRect(x: 0, y: 100, width: 200, height: 100), ctx: ctx)
        })
        let bitmap = try #require(Bitmap(drawn))
        // The band covers the top quarter of a 100 px-tall destination starting at y = 100.
        #expect(bitmap.pixel(x: 100, y: 110).a > 0.9, "the band should land at the top of the rect")
        #expect(bitmap.pixel(x: 100, y: 190).a < 0.1, "nothing should land at the bottom of the rect")
    }

    @Test("Coverage.make keeps the mask right-side-up")
    func coverageOrientation() throws {
        let coverage = try #require(Coverage.make(from: try probe,
                                                  pixelSize: CGSize(width: 200, height: 200),
                                                  source: .alpha))
        let halves = try #require(Bitmap(coverage)).alphaHalves
        #expect(halves.top > halves.bottom * 4,
                "coverage should stay top-heavy, got top \(halves.top) vs bottom \(halves.bottom)")
    }

    @Test("the emoji font path renders text right-side-up")
    func emojiFontOrientation() throws {
        // "L" is the cheapest asymmetric glyph: a thin stem on top, a foot at the bottom.
        let drawn = try #require(Raster.image(pixelWidth: 200, pixelHeight: 200) { _ in
            let font = NSFont.systemFont(ofSize: 150, weight: .bold)
            NSAttributedString(string: "L", attributes: [.font: font, .foregroundColor: NSColor.white])
                .draw(with: CGRect(x: 0, y: 0, width: 200, height: 200),
                      options: [.usesLineFragmentOrigin, .usesFontLeading])
        })
        let halves = try #require(Bitmap(drawn)).alphaHalves
        #expect(halves.bottom > halves.top * 1.1,
                "an 'L' is bottom-heavy; got top \(halves.top) vs bottom \(halves.bottom)")
    }

    // MARK: - Full renders

    /// Every overlay kind, rendered with the top-heavy probe: the ink must end up in the
    /// **upper** part of the overlay's own layout box.
    @Test("every overlay kind renders the right way up", arguments: [
        GraphicOverlay.bundledSymbol(catalog: "probe", name: "probe"),
        .emoji("🔺"),
        .image(fileName: "probe.png", mode: .over),
        .image(fileName: "probe.png", mode: .fill),
        .image(fileName: "probe.png", mode: .stamp),
        .image(fileName: "probe.png", mode: .only)
    ])
    func overlayOrientation(graphic: GraphicOverlay) throws {
        let resources = ProbeRenderResources(probe: try probe)
        let canvas: CGFloat = 512
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)),
                               canvas: canvas, resources: EmptyRenderResources())
        let style = Style(name: "Probe", fill: .solid(RenderFixtures.blue), graphic: graphic)
        let bitmap = try render(style, canvas: canvas, resources: resources)

        let centroid = try #require(bitmap.changeCentroidY(from: plain),
                                    "\(graphic) drew nothing")
        // Where the box the overlay is laid out in sits, as a fraction of the canvas.
        let geo = FolderGeometry(canvas: canvas)
        let box: CGRect
        switch graphic {
        case .image(_, .fill), .image(_, .over): box = geo.frontPanel
        case .image(_, .only): box = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        default: box = FolderIconRenderer.graphicBox(geo: geo, withText: false)
        }
        let middle = Double(box.midY / canvas)
        #expect(centroid < middle,
                "\(graphic) rendered upside down: ink centroid \(centroid) is below the box centre \(middle)")
    }

    @Test("an SF Symbol renders the right way up")
    func sfSymbolOrientation() throws {
        let canvas: CGFloat = 512
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)),
                               canvas: canvas, resources: EmptyRenderResources())
        // A solid up-triangle: unmistakably heavier at the bottom when the right way up.
        let style = Style(name: "Arrow", fill: .solid(RenderFixtures.blue),
                          graphic: .sfSymbol(name: "arrowtriangle.up.fill"))
        let bitmap = try render(style, canvas: canvas, resources: EmptyRenderResources())
        guard bitmap.differenceFraction(from: plain) > 0.001 else { return } // symbol unavailable
        let centroid = try #require(bitmap.changeCentroidY(from: plain))
        let box = FolderIconRenderer.graphicBox(geo: FolderGeometry(canvas: canvas), withText: false)
        #expect(centroid > Double(box.midY / canvas),
                "a solid up-triangle is bottom-heavy; centroid \(centroid)")
    }

    @Test("a bundled SVG symbol renders the right way up")
    func bundledSymbolOrientation() throws {
        guard let assets = RenderFixtures.assetsDirectory else { return }
        let resources = DirectoryRenderResources(baseURL: assets)
        guard resources.symbolImage(catalog: "lucide", name: "arrow-up") != nil else { return }
        let canvas: CGFloat = 512
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)),
                               canvas: canvas, resources: resources)
        let style = Style(name: "Arrow", fill: .solid(RenderFixtures.blue),
                          graphic: .bundledSymbol(catalog: "lucide", name: "arrow-up"))
        let bitmap = try render(style, canvas: canvas, resources: resources)
        let centroid = try #require(bitmap.changeCentroidY(from: plain))
        let box = FolderIconRenderer.graphicBox(geo: FolderGeometry(canvas: canvas), withText: false)
        #expect(centroid < Double(box.midY / canvas),
                "lucide's arrow-up is top-heavy (the head outweighs the stem); centroid \(centroid)")
    }

    @Test("a text overlay renders the right way up")
    func textOrientation() throws {
        let canvas: CGFloat = 512
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)),
                               canvas: canvas, resources: EmptyRenderResources())
        var style = Style(name: "L", fill: .solid(RenderFixtures.blue))
        style.text = TextOverlay(text: "L")
        style.text?.effects.emboss = false
        style.text?.effects.fill = true
        let bitmap = try render(style, canvas: canvas, resources: EmptyRenderResources())

        // Split the changed ink into halves of the text's own box rather than of the canvas.
        let metrics = try #require(FolderIconRenderer.textMetrics(for: style, canvas: canvas))
        let centroid = try #require(bitmap.changeCentroidY(from: plain))
        #expect(centroid > Double(metrics.box.midY / canvas),
                "an 'L' is bottom-heavy; centroid \(centroid) vs box centre \(metrics.box.midY / canvas)")
    }
}

// MARK: - Image "over" clipping

@Suite("Image over mode", .serialized)
struct ImageOverClippingTests {

    private func render(_ style: Style, canvas: CGFloat, resources: RenderResources) throws -> Bitmap {
        try #require(Bitmap(FolderIconRenderer.renderIcon(style: style, canvas: canvas, resources: resources)))
    }

    /// Zoom in, pan around: whatever falls outside the folder must be cropped away, which means
    /// the icon's alpha channel is untouched no matter how the image is transformed.
    @Test("a zoomed and panned image never paints outside the folder", arguments: [
        (3.0, 0.0, 0.0), (2.5, 0.25, -0.2), (2.5, -0.3, 0.25), (6.0, 0.0, 0.0)
    ])
    func overModeClipsToSilhouette(scale: Double, dx: Double, dy: Double) throws {
        let canvas: CGFloat = 512
        let resources = RenderFixtures.resources(userImages: RenderFixtures.workDirectory)
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)),
                               canvas: canvas, resources: resources)
        var style = Style(name: "Over", fill: .solid(RenderFixtures.blue),
                          graphic: .image(fileName: RenderFixtures.photoFileName, mode: .over))
        style.graphicTransform.scale = scale
        style.graphicTransform.offsetX = dx
        style.graphicTransform.offsetY = dy
        let bitmap = try render(style, canvas: canvas, resources: resources)

        #expect(bitmap.maxAlphaDifference(from: plain) < 0.03,
                "scale \(scale) offset (\(dx), \(dy)) painted outside the folder silhouette")
        // …and the crop still shows something inside it.
        #expect(bitmap.differenceFraction(from: plain) > 0.10,
                "the visible crop disappeared entirely")
    }

    @Test("panning changes which part of the image is visible")
    func panningChangesTheCrop() throws {
        let canvas: CGFloat = 512
        let resources = RenderFixtures.resources(userImages: RenderFixtures.workDirectory)
        func crop(dx: Double) throws -> Bitmap {
            var style = Style(name: "Over", fill: .solid(RenderFixtures.blue),
                              graphic: .image(fileName: RenderFixtures.photoFileName, mode: .over))
            style.graphicTransform.scale = 2.5
            style.graphicTransform.offsetX = dx
            return try render(style, canvas: canvas, resources: resources)
        }
        #expect(try crop(dx: -0.2).differenceFraction(from: try crop(dx: 0.2)) > 0.05)
    }

    @Test("a rotated, oversized image still stays inside the folder")
    func rotationStaysClipped() throws {
        let canvas: CGFloat = 512
        let resources = RenderFixtures.resources(userImages: RenderFixtures.workDirectory)
        let plain = try render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)),
                               canvas: canvas, resources: resources)
        var style = Style(name: "Over", fill: .solid(RenderFixtures.blue),
                          graphic: .image(fileName: RenderFixtures.photoFileName, mode: .over))
        style.graphicTransform.scale = 3
        style.graphicTransform.rotationDegrees = 30
        let bitmap = try render(style, canvas: canvas, resources: resources)
        #expect(bitmap.maxAlphaDifference(from: plain) < 0.03)
    }
}
