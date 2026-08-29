import AppKit
import Testing
#if canImport(FolderistCore)
@testable import FolderistCore
#else
@testable import Folderist
#endif

/// Checks our folder against the *measurements* of the macOS system folder icon.
///
/// The reference PNG is never bundled or copied — it is only ever read to compare numbers, and
/// every test here skips cleanly when `FOLDERIST_REFERENCE_ICON` is unset or missing, so a
/// checkout without it still passes.
@Suite("Folder shape and palette", .serialized)
struct FolderShapeTests {

    private func renderDefaultBlue(_ canvas: CGFloat) -> Bitmap? {
        let style = Style(name: "Blue", fill: .solid(.folderBlue))
        return Bitmap(FolderIconRenderer.renderIcon(style: style, canvas: canvas,
                                                    resources: EmptyRenderResources()))
    }

    // MARK: - Proportions

    @Test("the geometry constants are self-consistent and correctly ordered")
    func geometryOrdering() throws {
        let geo = FolderGeometry(canvas: 1024)
        #expect(geo.left < geo.right)
        #expect(geo.backTop < geo.shoulderTop)
        #expect(geo.shoulderTop < geo.frontTop)
        #expect(geo.frontTop < geo.lipTop)
        #expect(geo.lipTop < geo.bottom)
        // The tab occupies a bit over a third of the width, and hands over before the right edge.
        #expect(geo.tabRight > geo.left + geo.width * 0.3)
        #expect(geo.tabRight < geo.left + geo.width * 0.45)
        #expect(geo.tabSlant < geo.tabRight - geo.left)
        // Radii must fit inside their corners.
        #expect(geo.topRadius * 2 < geo.width)
        #expect(geo.bottomRadius * 2 < geo.width)
        #expect(geo.tabRadius < geo.tabRight - geo.left)
        // Everything is a pure scale of the canvas.
        let half = FolderGeometry(canvas: 512)
        #expect(abs(half.left * 2 - geo.left) < 0.001)
        #expect(abs(half.frontTop * 2 - geo.frontTop) < 0.001)
        #expect(abs(half.bottom * 2 - geo.bottom) < 0.001)
        #expect(abs(half.lipHeight * 2 - geo.lipHeight) < 0.001)
        // The stacked bands exactly fill the bottom of the front panel.
        let bands = geo.lipBands
        #expect(bands.count == geo.lipCount)
        #expect(abs(bands[0].minY - geo.lipTop) < 0.001)
        #expect(abs((bands.last?.maxY ?? 0) - geo.bottom) < 0.001)
    }

    @Test("the silhouette matches the system folder's proportions at 1024")
    func silhouetteMatchesReference() throws {
        guard let reference = RenderFixtures.referenceIcon else { return }
        #expect(reference.width == 1024)
        let ours = try #require(renderDefaultBlue(1024))

        /// Both bitmaps carry the same soft shadow, so the same estimator biases both alike;
        /// the *difference* is what matters.
        func compare(_ label: String, _ a: Double?, _ b: Double?, tolerance: Double = 2.0) {
            guard let a, let b else {
                Issue.record("\(label): could not measure (ref \(String(describing: a)), ours \(String(describing: b)))")
                return
            }
            #expect(abs(a - b) <= tolerance,
                    "\(label): reference \(a), ours \(b) — off by \(b - a) px at 1024")
        }

        compare("left edge",
                Bitmap.mean((400...600).map { reference.leftEdge(row: $0) }),
                Bitmap.mean((400...600).map { ours.leftEdge(row: $0) }))
        compare("right edge",
                Bitmap.mean((400...600).map { reference.rightEdge(row: $0) }),
                Bitmap.mean((400...600).map { ours.rightEdge(row: $0) }))
        compare("tab top edge",
                Bitmap.mean((120...280).map { reference.topEdge(column: $0) }),
                Bitmap.mean((120...280).map { ours.topEdge(column: $0) }))
        compare("shoulder top edge",
                Bitmap.mean((450...900).map { reference.topEdge(column: $0) }),
                Bitmap.mean((450...900).map { ours.topEdge(column: $0) }))
        compare("bottom edge",
                Bitmap.mean((200...800).map { reference.bottomEdge(column: $0) }),
                Bitmap.mean((200...800).map { ours.bottomEdge(column: $0) }))

        // The tab's S-curve, sampled across the whole transition.
        for x in stride(from: 310, through: 400, by: 10) {
            compare("tab curve at x=\(x)", reference.topEdge(column: x), ours.topEdge(column: x))
        }
        // The tab's rounded top-left corner.
        for y in stride(from: 145, through: 190, by: 15) {
            compare("tab corner at y=\(y)", reference.leftEdge(row: y), ours.leftEdge(row: y))
        }
        // The bottom-left corner.
        for y in stride(from: 860, through: 878, by: 6) {
            compare("bottom corner at y=\(y)", reference.leftEdge(row: y), ours.leftEdge(row: y))
        }
    }

    @Test("the front panel's top edge sits where the system folder's does")
    func frontPanelEdgeMatchesReference() throws {
        guard let reference = RenderFixtures.referenceIcon else { return }
        let ours = try #require(renderDefaultBlue(1024))

        /// The front panel is darker than the tab, so its top edge is the biggest luminance drop.
        func frontEdge(_ bitmap: Bitmap, column x: Int) -> Int {
            var best = -1, drop: Float = 0
            for y in 230..<300 {
                let above = bitmap.pixel(x: x, y: y - 1), below = bitmap.pixel(x: x, y: y + 1)
                let d = (above.r + above.g + above.b) - (below.r + below.g + below.b)
                if d > drop { drop = d; best = y }
            }
            return best
        }
        for x in stride(from: 200, through: 800, by: 150) {
            let a = frontEdge(reference, column: x), b = frontEdge(ours, column: x)
            #expect(abs(a - b) <= 2, "front-panel top edge at x=\(x): reference \(a), ours \(b)")
        }
    }

    // MARK: - Palette

    @Test("a default-blue folder's average colour matches the system folder's")
    func averageColourMatchesReference() throws {
        guard let reference = RenderFixtures.referenceIcon else { return }
        let ours = try #require(renderDefaultBlue(1024))
        let a = reference.averageColor, b = ours.averageColor
        #expect(abs(a.r - b.r) < 0.03, "red: reference \(a.r), ours \(b.r)")
        #expect(abs(a.g - b.g) < 0.03, "green: reference \(a.g), ours \(b.g)")
        #expect(abs(a.b - b.b) < 0.03, "blue: reference \(a.b), ours \(b.b)")
    }

    @Test("the tab and front-panel colours match the system folder row for row")
    func panelColoursMatchReference() throws {
        guard let reference = RenderFixtures.referenceIcon else { return }
        let ours = try #require(renderDefaultBlue(1024))

        // Tab: flat, sampled where only the tab exists.
        for y in stride(from: 150, through: 250, by: 25) {
            let a = reference.averageRow(y, from: 120, to: 280)
            let b = ours.averageRow(y, from: 120, to: 280)
            #expect(abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02,
                    "tab row \(y): reference \(a), ours \(b)")
        }
        // Front panel: the smooth gradient, away from the fold lines at the bottom.
        for y in stride(from: 280, through: 780, by: 50) {
            let a = reference.averageRow(y, from: 300, to: 700)
            let b = ours.averageRow(y, from: 300, to: 700)
            #expect(abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02,
                    "front-panel row \(y): reference \(a), ours \(b)")
        }
    }

    @Test("the folder reads as a folder at every icon-set size")
    func sizeLadderStaysReadable() throws {
        for size in FolderIconRenderer.iconSetSizes {
            let bitmap = try #require(renderDefaultBlue(CGFloat(size)))
            let geo = FolderGeometry(canvas: CGFloat(size))
            // The tab exists and is lighter than the front panel directly below it.
            let x = Int(geo.left + geo.width * 0.20)
            let tab = bitmap.pixel(x: x, y: Int((geo.backTop + geo.frontTop) / 2))
            let front = bitmap.pixel(x: x, y: Int(geo.frontTop + geo.frontPanel.height * 0.3))
            #expect(tab.a > 0.85, "size \(size): no tab at \(x)")
            #expect(front.a > 0.85, "size \(size): no front panel at \(x)")
            #expect(tab.r + tab.g + tab.b > front.r + front.g + front.b,
                    "size \(size): the tab lost its lighter shade")
            // The notch to the right of the tab stays empty.
            let notch = bitmap.pixel(x: Int(geo.right - geo.width * 0.05),
                                     y: Int(geo.backTop + (geo.shoulderTop - geo.backTop) * 0.3))
            #expect(notch.a < 0.5, "size \(size): the tab notch filled in")
        }
    }
}
