import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

@Suite("FolderIconRenderer", .serialized)
struct FolderIconRendererTests {

    private var resources: RenderResources {
        RenderFixtures.resources(userImages: RenderFixtures.workDirectory)
    }

    private func render(_ style: Style, canvas: CGFloat = 256) -> Bitmap {
        let image = FolderIconRenderer.renderIcon(style: style, canvas: canvas, resources: resources)
        guard let bitmap = Bitmap(image) else {
            Issue.record("render produced no bitmap")
            return Bitmap(CGImage.blank(1))!
        }
        return bitmap
    }

    // MARK: - Smoke

    @Test("renders a non-empty icon at every icon-set size")
    func rendersAtAllSizes() throws {
        let style = Style(name: "Blue", fill: .solid(RenderFixtures.blue))
        for size in FolderIconRenderer.iconSetSizes {
            let bitmap = render(style, canvas: CGFloat(size))
            #expect(bitmap.width == size)
            #expect(bitmap.height == size)
            let coverage = Double(bitmap.opaquePixelCount) / Double(size * size)
            #expect(coverage > 0.30, "size \(size) covered only \(coverage) of the canvas")
            #expect(coverage < 0.90, "size \(size) covered \(coverage) — the folder should not fill the canvas")
        }
    }

    @Test("renderIconSet returns every size keyed by pixel size")
    func iconSetSizes() throws {
        let set = FolderIconRenderer.renderIconSet(style: Style(name: "Blue"), resources: resources)
        #expect(Set(set.keys) == Set(FolderIconRenderer.iconSetSizes))
        for (size, image) in set {
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(cg.width == size)
            #expect(cg.height == size)
        }
    }

    @Test("multi-representation image carries every size")
    func multiRepresentation() throws {
        let image = FolderIconRenderer.renderMultiRepresentationImage(style: Style(name: "Blue"),
                                                                      resources: resources)
        let pixelSizes = Set(image.representations.map(\.pixelsWide))
        #expect(pixelSizes.isSuperset(of: Set(FolderIconRenderer.iconSetSizes)))
    }

    @Test("rendering is deterministic")
    func deterministic() throws {
        let style = Style(name: "Both", fill: .solid(RenderFixtures.green),
                          graphic: .sfSymbol(name: "star.fill"),
                          text: TextOverlay(text: "Hi"))
        let a = render(style, canvas: 128)
        let b = render(style, canvas: 128)
        #expect(a.differenceFraction(from: b) == 0)
    }

    // MARK: - Fill

    @Test("a solid fill and a gradient fill produce different pixels")
    func solidVersusGradient() throws {
        let solid = render(Style(name: "S", fill: .solid(RenderFixtures.blue)))
        let gradient = render(Style(name: "G", fill: .gradient(RenderFixtures.blue,
                                                               RenderFixtures.orange,
                                                               angleDegrees: 90)))
        #expect(solid.differenceFraction(from: gradient) > 0.20)
    }

    @Test("the gradient angle changes the render")
    func gradientAngleMatters() throws {
        let a = render(Style(name: "A", fill: .gradient(RenderFixtures.blue, RenderFixtures.orange, angleDegrees: 0)))
        let b = render(Style(name: "B", fill: .gradient(RenderFixtures.blue, RenderFixtures.orange, angleDegrees: 90)))
        #expect(a.differenceFraction(from: b) > 0.20)
    }

    @Test("changing the hue moves the average colour to the new hue")
    func hueChangesAverageColour() throws {
        let red = render(Style(name: "R", fill: .solid(RenderFixtures.red))).averageColor
        let green = render(Style(name: "G", fill: .solid(RenderFixtures.green))).averageColor
        let blue = render(Style(name: "B", fill: .solid(RenderFixtures.blue))).averageColor

        #expect(red.r > red.g && red.r > red.b)
        #expect(green.g > green.r && green.g > green.b)
        #expect(blue.b > blue.r && blue.b > blue.g)

        // The rendered colour must track the requested colour, not merely differ from it.
        #expect(abs(red.r - Float(RenderFixtures.red.red)) < 0.20)
        #expect(abs(blue.b - Float(RenderFixtures.blue.blue)) < 0.20)
    }

    @Test("the back panel is lighter than the front panel for both fill kinds")
    func panelShading() throws {
        // The system folder's tab is a *lighter* wash of the base colour than the front panel —
        // the front panel is the one carrying the saturated colour. Our shading model matches it.
        for fill in [FolderFill.solid(RenderFixtures.blue),
                     .gradient(RenderFixtures.blue, RenderFixtures.blue, angleDegrees: 45)] {
            let bitmap = render(Style(name: "P", fill: fill), canvas: 512)
            let geo = FolderGeometry(canvas: 512)
            let tab = bitmap.pixel(x: Int(geo.left + geo.width * 0.10),
                                   y: Int(geo.backTop + (geo.frontTop - geo.backTop) * 0.45))
            let front = bitmap.pixel(x: Int(geo.left + geo.width * 0.10),
                                     y: Int(geo.frontTop + geo.frontPanel.height * 0.25))
            #expect(tab.a > 0.9 && front.a > 0.9)
            let tabLum = tab.r + tab.g + tab.b
            let frontLum = front.r + front.g + front.b
            #expect(tabLum > frontLum, "tab (\(tabLum)) should be lighter than the front panel (\(frontLum))")
        }
    }

    @Test("the front panel ends with the system folder's stacked fold lines")
    func frontPanelLipBands() throws {
        let bitmap = render(Style(name: "P", fill: .solid(RenderFixtures.blue)), canvas: 1024)
        let geo = FolderGeometry(canvas: 1024)
        #expect(geo.lipCount == 3)
        let x0 = Int(geo.left + geo.width * 0.3), x1 = Int(geo.left + geo.width * 0.7)
        for band in geo.lipBands {
            let fold = bitmap.averageRow(Int(band.minY) + 1, from: x0, to: x1)
            let crease = bitmap.averageRow(Int(band.maxY) - 2, from: x0, to: x1)
            #expect(fold.r > crease.r + 0.05,
                    "each band should open with a bright fold line and end dark; got \(fold) then \(crease)")
        }
    }

    // MARK: - Graphic overlays

    @Test("an SF Symbol overlay changes pixels on the front panel")
    func sfSymbolOverlay() throws {
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)))
        let symbol = render(Style(name: "Symbol", fill: .solid(RenderFixtures.blue),
                                  graphic: .sfSymbol(name: "star.fill")))
        #expect(symbol.differenceFraction(from: plain) > 0.02)
    }

    @Test("a bundled SVG symbol resolves and renders")
    func bundledSymbolOverlay() throws {
        guard let assets = RenderFixtures.assetsDirectory else { return }
        let res = DirectoryRenderResources(baseURL: assets)
        #expect(res.symbolImage(catalog: "lucide", name: "camera") != nil)
        // Phosphor lives one level deeper (regular/ and fill/) — the provider must find it.
        #expect(res.symbolImage(catalog: "phosphor", name: "camera") != nil)

        let plain = FolderIconRenderer.renderIcon(style: Style(name: "P", fill: .solid(RenderFixtures.blue)),
                                                  canvas: 256, resources: res)
        let withSymbol = FolderIconRenderer.renderIcon(
            style: Style(name: "S", fill: .solid(RenderFixtures.blue),
                         graphic: .bundledSymbol(catalog: "lucide", name: "camera")),
            canvas: 256, resources: res)
        let a = try #require(Bitmap(plain)), b = try #require(Bitmap(withSymbol))
        #expect(b.differenceFraction(from: a) > 0.02)
    }

    @Test("an emoji overlay renders in colour")
    func emojiOverlay() throws {
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)))
        let emoji = render(Style(name: "Emoji", fill: .solid(RenderFixtures.blue), graphic: .emoji("🚀")))
        #expect(emoji.differenceFraction(from: plain) > 0.02)

        // Emoji artwork must keep its own colours rather than being tinted to the folder hue.
        let geo = FolderGeometry(canvas: 256)
        var sawNonBlueish = false
        let box = FolderIconRenderer.graphicBox(geo: geo, withText: false)
        for y in stride(from: Int(box.minY), to: Int(box.maxY), by: 3) {
            for x in stride(from: Int(box.minX), to: Int(box.maxX), by: 3) {
                let p = emoji.pixel(x: x, y: y)
                if p.a > 0.9 && p.r > p.b + 0.15 { sawNonBlueish = true }
            }
        }
        #expect(sawNonBlueish, "emoji should retain its own colours over a blue folder")
    }

    @Test("effects change the overlay: emboss vs fill vs strokes vs shadow")
    func overlayEffects() throws {
        let base = Style(name: "FX", fill: .solid(RenderFixtures.blue), graphic: .sfSymbol(name: "star.fill"))
        let embossed = render(base)

        var filledEffects = OverlayEffects()
        filledEffects.emboss = false
        filledEffects.fill = true
        var filled = base
        filled.graphicEffects = filledEffects
        #expect(render(filled).differenceFraction(from: embossed) > 0.01)

        var strokedEffects = OverlayEffects()
        strokedEffects.outerStroke = true
        var stroked = base
        stroked.graphicEffects = strokedEffects
        #expect(render(stroked).differenceFraction(from: embossed) > 0.005)

        var shadowEffects = OverlayEffects()
        shadowEffects.shadow = true
        var shadowed = base
        shadowed.graphicEffects = shadowEffects
        #expect(render(shadowed).differenceFraction(from: embossed) > 0.005)

        var innerEffects = OverlayEffects()
        innerEffects.innerStroke = true
        var innerStroked = base
        innerStroked.graphicEffects = innerEffects
        #expect(render(innerStroked).differenceFraction(from: embossed) > 0.002)
    }

    @Test("zero opacity hides the overlay entirely")
    func zeroOpacityHidesOverlay() throws {
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)))
        var hidden = Style(name: "Hidden", fill: .solid(RenderFixtures.blue),
                           graphic: .sfSymbol(name: "star.fill"))
        hidden.graphicEffects.opacity = 0
        #expect(render(hidden).differenceFraction(from: plain) == 0)
    }

    @Test("an explicit tint colours the overlay")
    func tintedOverlay() throws {
        var style = Style(name: "Tint", fill: .solid(RenderFixtures.blue), graphic: .sfSymbol(name: "square.fill"))
        style.graphicEffects.emboss = false
        style.graphicEffects.fill = true
        style.graphicEffects.tint = StyleColor(red: 1, green: 0, blue: 0)
        let bitmap = render(style, canvas: 512)
        let geo = FolderGeometry(canvas: 512)
        let box = FolderIconRenderer.graphicBox(geo: geo, withText: false)
        let centre = bitmap.pixel(x: Int(box.midX), y: Int(box.midY))
        #expect(centre.r > 0.75 && centre.g < 0.35 && centre.b < 0.35,
                "expected a red tint, got \(centre)")
    }

    // MARK: - Transforms

    @Test("an overlay offset moves pixels")
    func transformOffsetMovesOverlay() throws {
        let centred = Style(name: "C", fill: .solid(RenderFixtures.blue), graphic: .sfSymbol(name: "star.fill"))
        var moved = centred
        moved.graphicTransform.offsetX = 0.15
        #expect(render(moved).differenceFraction(from: render(centred)) > 0.01)
    }

    @Test("overlay scale and rotation change the render")
    func transformScaleAndRotation() throws {
        let base = Style(name: "C", fill: .solid(RenderFixtures.blue), graphic: .sfSymbol(name: "star.fill"))
        var scaled = base
        scaled.graphicTransform.scale = 1.6
        var rotated = base
        rotated.graphicTransform.rotationDegrees = 35
        let plain = render(base)
        #expect(render(scaled).differenceFraction(from: plain) > 0.01)
        #expect(render(rotated).differenceFraction(from: plain) > 0.01)
    }

    @Test("transformed() applies scale about the centre and offsets in canvas fractions")
    func transformMath() throws {
        let box = CGRect(x: 100, y: 100, width: 200, height: 200)
        var t = OverlayTransform()
        t.scale = 2
        t.offsetX = 0.1
        t.offsetY = -0.05
        let out = FolderIconRenderer.transformed(box, t, canvas: 1000)
        #expect(out.width == 400 && out.height == 400)
        #expect(abs(out.midX - 300) < 0.001)
        #expect(abs(out.midY - 150) < 0.001)
    }

    // MARK: - Text

    @Test("auto-fit text never overflows its budget", arguments: [
        "A", "42", "2026", "ARCHIVE", "Work in progress", "WWWWWWWWWWWW", "iiii"
    ])
    func autoFitTextFits(text: String) throws {
        for canvas in [CGFloat(128), 256, 1024] {
            var style = Style(name: "T", fill: .solid(RenderFixtures.blue))
            style.text = TextOverlay(text: text)
            let metrics = try #require(FolderIconRenderer.textMetrics(for: style, canvas: canvas))
            #expect(metrics.didAutoFit)
            #expect(metrics.size.width <= metrics.limit.width + 0.5,
                    "\"\(text)\" width \(metrics.size.width) > \(metrics.limit.width) at canvas \(canvas)")
            #expect(metrics.size.height <= metrics.limit.height + 0.5,
                    "\"\(text)\" height \(metrics.size.height) > \(metrics.limit.height) at canvas \(canvas)")
            // And the budget must itself sit inside the front panel.
            #expect(metrics.limit.width <= metrics.panel.width)
            #expect(metrics.limit.height <= metrics.panel.height)
            #expect(metrics.box.minX >= metrics.panel.minX - 0.5)
            #expect(metrics.box.maxX <= metrics.panel.maxX + 0.5)
            #expect(metrics.box.minY >= metrics.panel.minY - 0.5)
            #expect(metrics.box.maxY <= metrics.panel.maxY + 0.5)
            #expect(metrics.pointSize > 1)
        }
    }

    @Test("auto-fit picks a bigger size for shorter text")
    func autoFitScalesWithLength() throws {
        func size(_ text: String) -> CGFloat {
            var style = Style(name: "T", fill: .solid(RenderFixtures.blue))
            style.text = TextOverlay(text: text)
            return FolderIconRenderer.textMetrics(for: style, canvas: 1024)?.pointSize ?? 0
        }
        #expect(size("A") > size("ARCHIVE"))
        #expect(size("ARCHIVE") > size("A VERY LONG FOLDER NAME"))
    }

    @Test("an explicit point size is honoured and scales with the canvas")
    func explicitPointSize() throws {
        var style = Style(name: "T", fill: .solid(RenderFixtures.blue))
        var text = TextOverlay(text: "Hi")
        text.pointSize = 200
        style.text = text
        let big = try #require(FolderIconRenderer.textMetrics(for: style, canvas: 1024))
        let small = try #require(FolderIconRenderer.textMetrics(for: style, canvas: 512))
        #expect(!big.didAutoFit)
        #expect(big.pointSize == 200)
        #expect(small.pointSize == 100)
    }

    @Test("text renders and moves the pixels of the front panel")
    func textRenders() throws {
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)), canvas: 512)
        var style = Style(name: "T", fill: .solid(RenderFixtures.blue))
        style.text = TextOverlay(text: "2026")
        #expect(render(style, canvas: 512).differenceFraction(from: plain) > 0.01)
    }

    @Test("text and a graphic coexist without sharing the same layout box")
    func textAndGraphicCoexist() throws {
        let geo = FolderGeometry(canvas: 1024)
        let graphicAlone = FolderIconRenderer.graphicBox(geo: geo, withText: false)
        let graphicWithText = FolderIconRenderer.graphicBox(geo: geo, withText: true)
        let textWithGraphic = FolderIconRenderer.textBox(geo: geo, withGraphic: true)
        #expect(graphicWithText.width < graphicAlone.width)
        #expect(graphicWithText.maxY <= textWithGraphic.minY + 1,
                "the graphic should sit above the text")
        #expect(textWithGraphic.maxY <= geo.frontPanel.maxY)

        var style = Style(name: "Both", fill: .solid(RenderFixtures.blue),
                          graphic: .sfSymbol(name: "star.fill"))
        style.text = TextOverlay(text: "Work")
        let both = render(style, canvas: 512)
        let symbolOnly = render(Style(name: "S", fill: .solid(RenderFixtures.blue),
                                      graphic: .sfSymbol(name: "star.fill")), canvas: 512)
        #expect(both.differenceFraction(from: symbolOnly) > 0.01)
    }

    @Test("a font family + face resolves through NSFontManager")
    func fontResolution() throws {
        let bold = FolderIconRenderer.resolveFont(family: "Helvetica Neue", face: "Bold", size: 64)
        let light = FolderIconRenderer.resolveFont(family: "Helvetica Neue", face: "Light", size: 64)
        #expect(bold.pointSize == 64)
        #expect(bold.fontName != light.fontName)
        // An unknown family must still yield a usable font rather than crashing.
        let fallback = FolderIconRenderer.resolveFont(family: "No Such Family 123", face: "Regular", size: 32)
        #expect(fallback.pointSize == 32)
    }

    // MARK: - Image modes

    @Test("every ImageMode renders something distinct")
    func allImageModesRender() throws {
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)), canvas: 256)
        var results: [ImageMode: Bitmap] = [:]
        for mode in ImageMode.allCases {
            let style = Style(name: mode.rawValue, fill: .solid(RenderFixtures.blue),
                              graphic: .image(fileName: RenderFixtures.photoFileName, mode: mode))
            let bitmap = render(style, canvas: 256)
            #expect(bitmap.opaquePixelCount > 1000, "\(mode) rendered almost nothing")
            #expect(bitmap.differenceFraction(from: plain) > 0.05, "\(mode) looks like a plain folder")
            results[mode] = bitmap
        }
        // The four modes must all differ from one another.
        let modes = ImageMode.allCases
        for i in 0..<modes.count {
            for j in (i + 1)..<modes.count {
                let a = try #require(results[modes[i]]), b = try #require(results[modes[j]])
                #expect(a.differenceFraction(from: b) > 0.02,
                        "\(modes[i]) and \(modes[j]) render alike")
            }
        }
    }

    @Test("image fill stays inside the folder silhouette")
    func imageFillIsClipped() throws {
        let style = Style(name: "Fill", fill: .solid(RenderFixtures.blue),
                          graphic: .image(fileName: RenderFixtures.photoFileName, mode: .fill))
        let bitmap = render(style, canvas: 256)
        // Corners of the canvas are outside the folder and must stay transparent.
        for (fx, fy) in [(0.01, 0.01), (0.99, 0.01), (0.01, 0.99), (0.99, 0.99)] {
            #expect(bitmap.pixel(fx: fx, fy: fy).a < 0.01)
        }
        // The tab is above the front panel, so it keeps the folder colour.
        let geo = FolderGeometry(canvas: 256)
        let tab = bitmap.pixel(x: Int(geo.left + geo.width * 0.12),
                               y: Int(geo.backTop + (geo.shoulderTop - geo.backTop) * 0.5))
        #expect(tab.a > 0.9)
        #expect(tab.b > tab.r, "the tab should still be blue, got \(tab)")

        // The fill must not change the icon's silhouette, even scaled well past the panel.
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)), canvas: 256)
        #expect(bitmap.maxAlphaDifference(from: plain) < 0.03)
        var scaled = style
        scaled.graphicTransform.scale = 2.5
        #expect(render(scaled, canvas: 256).maxAlphaDifference(from: plain) < 0.03)
    }

    @Test("image only drops the folder shape")
    func imageOnlyDropsFolder() throws {
        let only = render(Style(name: "Only", fill: .solid(RenderFixtures.blue),
                                graphic: .image(fileName: RenderFixtures.photoFileName, mode: .only)),
                          canvas: 256)
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.blue)), canvas: 256)
        #expect(only.differenceFraction(from: plain) > 0.30)

        // The square photo covers the canvas edge-to-edge where the folder had a notch.
        let geo = FolderGeometry(canvas: 256)
        let notch = (x: Int(geo.right - geo.width * 0.05), y: Int(geo.backTop + 2))
        #expect(plain.pixel(x: notch.x, y: notch.y).a < 0.05)
        #expect(only.pixel(x: notch.x, y: notch.y).a > 0.5)
    }

    @Test("stamping a white square differs from drawing it over the folder")
    func whiteSquareStampVersusOver() throws {
        let stamped = render(Style(name: "Stamp", fill: .solid(RenderFixtures.orange),
                                   graphic: .image(fileName: RenderFixtures.whiteSquareFileName, mode: .stamp)),
                             canvas: 256)
        let over = render(Style(name: "Over", fill: .solid(RenderFixtures.orange),
                                graphic: .image(fileName: RenderFixtures.whiteSquareFileName, mode: .over)),
                          canvas: 256)
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.orange)), canvas: 256)

        #expect(stamped.differenceFraction(from: over) > 0.05)
        // Stamp reads luminance: a pure white image engraves nothing…
        #expect(stamped.differenceFraction(from: plain) < 0.01)
        // …while "over" paints a visible white block.
        #expect(over.differenceFraction(from: plain) > 0.10)
    }

    @Test("stamping a black-and-white image engraves its dark areas")
    func stampEngravesDarkAreas() throws {
        let stamped = render(Style(name: "Stamp", fill: .solid(RenderFixtures.orange),
                                   graphic: .image(fileName: RenderFixtures.stampFileName, mode: .stamp)),
                             canvas: 512)
        let plain = render(Style(name: "Plain", fill: .solid(RenderFixtures.orange)), canvas: 512)
        #expect(stamped.differenceFraction(from: plain) > 0.02)

        let geo = FolderGeometry(canvas: 512)
        let box = FolderIconRenderer.graphicBox(geo: geo, withText: false)
        // The stamp source is a black ring around a white centre: the ring engraves, the centre doesn't.
        let ring = stamped.pixel(x: Int(box.midX - box.width * 0.25), y: Int(box.midY))
        let hole = stamped.pixel(x: Int(box.midX + box.width * 0.10), y: Int(box.midY))
        let untouched = plain.pixel(x: Int(box.midX + box.width * 0.10), y: Int(box.midY))
        #expect(ring.r + ring.g + ring.b < untouched.r + untouched.g + untouched.b,
                "the dark part of the stamp should engrave darker")
        #expect(abs(hole.r - untouched.r) < 0.06, "the white part of the stamp should leave the folder alone")
    }

    @Test("a missing resource degrades to a plain folder instead of crashing")
    func missingResources() throws {
        let empty = EmptyRenderResources()
        for graphic in [GraphicOverlay.bundledSymbol(catalog: "nope", name: "nope"),
                        .image(fileName: "missing.png", mode: .fill),
                        .image(fileName: "missing.png", mode: .only),
                        .sfSymbol(name: "definitely.not.a.symbol.name")] {
            let style = Style(name: "X", fill: .solid(RenderFixtures.blue), graphic: graphic)
            let image = FolderIconRenderer.renderIcon(style: style, canvas: 64, resources: empty)
            let bitmap = try #require(Bitmap(image))
            #expect(bitmap.width == 64)
            if case .image(_, .only) = graphic {
                #expect(bitmap.opaquePixelCount == 0)
            } else {
                #expect(bitmap.opaquePixelCount > 500)
            }
        }
    }

    // MARK: - Resource providers

    @Test("emoji asset naming drops variation selectors")
    func emojiNaming() throws {
        #expect(EmojiAssetNaming.fileBaseName(for: "🚀") == "1f680")
        #expect(EmojiAssetNaming.fileBaseName(for: "❤️") == "2764")
        #expect(EmojiAssetNaming.fileBaseName(for: "🇦🇺") == "1f1e6-1f1fa")
    }

    @Test("bundled emoji artwork is used when the provider offers it")
    func bundledEmojiArtwork() throws {
        guard let assets = RenderFixtures.assetsDirectory,
              FileManager.default.fileExists(atPath: assets.appendingPathComponent("emoji/1f680.svg").path)
        else { return }
        let res = DirectoryRenderResources(baseURL: assets, preferBundledEmoji: true)
        #expect(res.emojiImage(for: "🚀") != nil)
        let style = Style(name: "E", fill: .solid(RenderFixtures.blue), graphic: .emoji("🚀"))
        let bundled = try #require(Bitmap(FolderIconRenderer.renderIcon(style: style, canvas: 256, resources: res)))
        let systemFont = render(style, canvas: 256)
        #expect(bundled.differenceFraction(from: systemFont) > 0.001)
    }
}

private extension CGImage {
    static func blank(_ size: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
