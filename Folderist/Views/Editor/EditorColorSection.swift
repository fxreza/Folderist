import AppKit
import SwiftUI

/// The always-visible color section along the bottom of the editor — the
/// equivalent of FolderMarker's floating Color panel (fm1): a color well,
/// hue and brightness strips, the Hex + R/G/B fields, the eyedropper, Color
/// Shuffle, and the solid ⇄ gradient switch with its second stop and angle.
struct EditorColorSection: View {
    @Binding var fill: FolderFill

    @State private var hexDraft: String = ""
    @FocusState private var hexFocused: Bool

    private var isGradient: Bool {
        if case .gradient = fill { return true }
        return false
    }

    private var primary: StyleColor { StyleColorMath.primaryColor(of: fill) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                swatch
                VStack(spacing: 6) {
                    HueSlider(hue: hueBinding)
                    brightnessStrip
                }
                .frame(width: 190)

                hexAndRGB

                Spacer(minLength: 0)

                Button {
                    sampleWithEyedropper()
                } label: {
                    Image(systemName: "eyedropper")
                }
                .buttonStyle(.borderless)
                .help("Pick a color from anywhere on screen")

                Button {
                    fill = StyleColorMath.settingPrimary(fill, to: StyleColorMath.shuffled())
                    syncHex()
                } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(.borderless)
                .help("Color Shuffle — a random folder color")

                // One click back to the stock macOS folder color (#2).
                // `StyleColor.folderBlue` is the single source of truth for
                // that shade, so this stays correct as it is recalibrated.
                Button("Default Blue") {
                    fill = .solid(.folderBlue)
                    syncHex()
                }
                .font(.system(size: 11))
                .help("Reset the folder to the standard macOS blue")
            }

            HStack(spacing: 10) {
                Picker("", selection: gradientBinding) {
                    Text("Solid").tag(false)
                    Text("Gradient").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)

                if isGradient {
                    ColorPicker("", selection: secondaryBinding, supportsOpacity: false)
                        .labelsHidden()
                        .help("Second gradient stop")
                    LabeledEditorSlider(label: "Angle", value: angleBinding, range: 0...360,
                                        display: { "\(Int($0))°" })
                        .frame(width: 260)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear(perform: syncHex)
        .onChange(of: primary) { _, _ in if !hexFocused { syncHex() } }
    }

    // MARK: Pieces

    private var swatch: some View {
        ColorPicker("", selection: primaryBinding, supportsOpacity: false)
            .labelsHidden()
            .scaleEffect(1.2)
            .frame(width: 48, height: 30)
            .help("Folder color")
    }

    /// Brightness ramp for the current hue/saturation — the vertical axis of
    /// FolderMarker's wheel-and-triangle, flattened into a strip.
    private var brightnessStrip: some View {
        let hsb = StyleColorMath.hsb(primary)
        return GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [Color(hue: hsb.h, saturation: hsb.s, brightness: 0),
                             Color(hue: hsb.h, saturation: hsb.s, brightness: 1)],
                    startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 6, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.45), lineWidth: 0.75)
                    )
                    .offset(x: min(max(0, hsb.b * width - 3), width - 6))
            }
            .frame(height: 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let b = StyleColorMath.clamp01(value.location.x / width)
                    let updated = StyleColorMath.fromHSB(h: hsb.h, s: hsb.s, b: b, alpha: primary.alpha)
                    fill = StyleColorMath.settingPrimary(fill, to: updated)
                }
            )
            .accessibilityLabel("Brightness")
        }
        .frame(height: 16)
    }

    private var hexAndRGB: some View {
        HStack(spacing: 6) {
            VStack(spacing: 1) {
                TextField("FFFFFF", text: $hexDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 76)
                    .focused($hexFocused)
                    .onSubmit(commitHex)
                    .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
                Text("Hex").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            channelField("R", \.red)
            channelField("G", \.green)
            channelField("B", \.blue)
        }
    }

    private func channelField(_ label: String,
                              _ keyPath: WritableKeyPath<StyleColor, Double>) -> some View {
        VStack(spacing: 1) {
            TextField("", value: Binding(
                get: { Int((primary[keyPath: keyPath] * 255).rounded()) },
                set: { newValue in
                    var color = primary
                    color[keyPath: keyPath] = Double(min(255, max(0, newValue))) / 255
                    fill = StyleColorMath.settingPrimary(fill, to: color)
                    syncHex()
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 42)
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    // MARK: Bindings

    private var primaryBinding: Binding<Color> {
        Binding(
            get: { primary.swiftUIColor },
            set: { fill = StyleColorMath.settingPrimary(fill, to: StyleColor(NSColor($0))); syncHex() }
        )
    }

    private var secondaryBinding: Binding<Color> {
        Binding(
            get: { StyleColorMath.secondaryColor(of: fill).swiftUIColor },
            set: { fill = StyleColorMath.settingSecondary(fill, to: StyleColor(NSColor($0))) }
        )
    }

    private var hueBinding: Binding<Double> {
        Binding(
            get: { StyleColorMath.primaryHue(of: fill) },
            set: { fill = StyleColorMath.settingHue(fill, to: $0); syncHex() }
        )
    }

    private var angleBinding: Binding<Double> {
        Binding(
            get: { if case .gradient(_, _, let a) = fill { return a }; return 45 },
            set: { fill = StyleColorMath.settingAngle(fill, to: $0) }
        )
    }

    /// Switching to gradient seeds a second stop a little way around the hue
    /// wheel, so the toggle produces a usable gradient immediately.
    private var gradientBinding: Binding<Bool> {
        Binding(
            get: { isGradient },
            set: { wantsGradient in
                switch (wantsGradient, fill) {
                case (true, .solid(let c)):
                    fill = .gradient(c, StyleColorMath.rotatingHue(c, by: 0.08), angleDegrees: 45)
                case (false, .gradient(let a, _, _)):
                    fill = .solid(a)
                default:
                    break
                }
            }
        )
    }

    // MARK: Hex / eyedropper

    private func syncHex() {
        hexDraft = StyleColorMath.hexString(primary)
    }

    private func commitHex() {
        guard let color = StyleColorMath.color(fromHex: hexDraft) else {
            syncHex()
            return
        }
        fill = StyleColorMath.settingPrimary(fill, to: color)
        syncHex()
    }

    private func sampleWithEyedropper() {
        NSColorSampler().show { sampled in
            guard let sampled else { return }
            fill = StyleColorMath.settingPrimary(fill, to: StyleColor(sampled))
            syncHex()
        }
    }
}
