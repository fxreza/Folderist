import AppKit
import SwiftUI

/// Color maths shared by the toolbar hue slider and the editor's color
/// section: hue rotation of a whole `FolderFill`, hex parsing/formatting and
/// the "Color Shuffle" random-but-pleasant generator.
enum StyleColorMath {

    // MARK: HSB

    /// Hue (0…1), saturation, brightness of a `StyleColor`.
    static func hsb(_ color: StyleColor) -> (h: Double, s: Double, b: Double) {
        let c = color.nsColor.srgb
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }

    static func fromHSB(h: Double, s: Double, b: Double, alpha: Double = 1) -> StyleColor {
        let color = NSColor(hue: CGFloat(wrap(h)), saturation: CGFloat(clamp01(s)),
                            brightness: CGFloat(clamp01(b)), alpha: CGFloat(clamp01(alpha)))
        return StyleColor(color)
    }

    /// Same saturation/brightness, new hue.
    static func settingHue(_ color: StyleColor, to hue: Double) -> StyleColor {
        let c = hsb(color)
        // A fully desaturated color has no meaningful hue to shift; give it
        // some saturation so dragging the rainbow slider does something.
        let saturation = c.s < 0.05 ? 0.65 : c.s
        let brightness = c.b < 0.05 ? 0.8 : c.b
        return fromHSB(h: hue, s: saturation, b: brightness, alpha: color.alpha)
    }

    static func rotatingHue(_ color: StyleColor, by delta: Double) -> StyleColor {
        let c = hsb(color)
        return settingHue(color, to: c.h + delta)
    }

    /// The hue the toolbar slider should show for a fill (first stop of a gradient).
    static func primaryHue(of fill: FolderFill) -> Double {
        switch fill {
        case .solid(let c): return hsb(c).h
        case .gradient(let a, _, _): return hsb(a).h
        }
    }

    /// Solid: set the hue outright. Gradient: rotate *both* stops by the
    /// delta between the current first-stop hue and the requested one, so the
    /// two-color relationship of the gradient survives the drag.
    static func settingHue(_ fill: FolderFill, to hue: Double) -> FolderFill {
        switch fill {
        case .solid(let c):
            return .solid(settingHue(c, to: hue))
        case .gradient(let a, let b, let angle):
            let delta = wrap(hue - hsb(a).h)
            return .gradient(rotatingHue(a, by: delta), rotatingHue(b, by: delta), angleDegrees: angle)
        }
    }

    /// First stop (or the solid color) — what the color well and hex field edit.
    static func primaryColor(of fill: FolderFill) -> StyleColor {
        switch fill {
        case .solid(let c): return c
        case .gradient(let a, _, _): return a
        }
    }

    static func secondaryColor(of fill: FolderFill) -> StyleColor {
        switch fill {
        case .solid(let c): return rotatingHue(c, by: 0.08)
        case .gradient(_, let b, _): return b
        }
    }

    static func settingPrimary(_ fill: FolderFill, to color: StyleColor) -> FolderFill {
        switch fill {
        case .solid: return .solid(color)
        case .gradient(_, let b, let angle): return .gradient(color, b, angleDegrees: angle)
        }
    }

    static func settingSecondary(_ fill: FolderFill, to color: StyleColor) -> FolderFill {
        switch fill {
        case .solid(let a): return .gradient(a, color, angleDegrees: 45)
        case .gradient(let a, _, let angle): return .gradient(a, color, angleDegrees: angle)
        }
    }

    static func settingAngle(_ fill: FolderFill, to angle: Double) -> FolderFill {
        switch fill {
        case .solid: return fill
        case .gradient(let a, let b, _): return .gradient(a, b, angleDegrees: angle)
        }
    }

    // MARK: Hex

    /// "#RRGGBB" (uppercase, no alpha — matching FolderMarker's Hex field).
    static func hexString(_ color: StyleColor) -> String {
        let c = color.nsColor.srgb
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", clampByte(r), clampByte(g), clampByte(b))
    }

    /// Accepts "#RGB", "RGB", "#RRGGBB", "RRGGBB".
    static func color(fromHex raw: String) -> StyleColor? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.allSatisfy({ $0.isHexDigit }) else { return nil }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return StyleColor(red: Double((value >> 16) & 0xFF) / 255,
                          green: Double((value >> 8) & 0xFF) / 255,
                          blue: Double(value & 0xFF) / 255)
    }

    // MARK: Shuffle

    /// A random color that still looks like a folder: saturated enough to
    /// read at 16 px, bright enough for the embossed overlays to show.
    static func shuffled() -> StyleColor {
        fromHSB(h: Double.random(in: 0...1),
                s: Double.random(in: 0.55...0.92),
                b: Double.random(in: 0.72...0.98))
    }

    // MARK: Small helpers

    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    /// Wraps a hue into 0…1.
    static func wrap(_ v: Double) -> Double {
        let m = v.truncatingRemainder(dividingBy: 1)
        return m < 0 ? m + 1 : m
    }

    private static func clampByte(_ v: Int) -> Int { min(255, max(0, v)) }
}

extension StyleColor {
    var swiftUIColor: Color { Color(nsColor: nsColor) }
}
