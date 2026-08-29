import AppKit
import SwiftUI

/// The editor's **Effects** tab: the `OverlayEffects` switches (shadow,
/// emboss, fill, inner/outer stroke), the opacity slider and the tint well.
///
/// The same set exists for the graphic overlay and the text overlay, so the
/// tab reuses the editor's shared Graphic | Text selector rather than
/// duplicating the controls.
struct EditorEffectsTab: View {
    @Binding var draft: Style
    @Binding var overlayTarget: OverlayTarget

    private var hasTarget: Bool {
        switch overlayTarget {
        case .graphic: return draft.graphic != nil
        case .text: return draft.text != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $overlayTarget) {
                ForEach(OverlayTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            if !hasTarget {
                Text(overlayTarget == .graphic
                     ? "This style has no icon, emoji or image yet — pick one in Icons, Generic or Image."
                     : "This style has no text yet — add some in the Text tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Emboss and Fill are one either/or choice, not two independent
            // switches — as two checkboxes they could both be on, which is
            // what made "Embossed" look permanently selected (#18).
            VStack(alignment: .leading, spacing: 6) {
                Text("Style")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                EmbossFlatPicker(effects: effects, isEnabled: hasTarget)
                    .help("Engrave the overlay into the folder color, or lay it on flat")
            }

            VStack(alignment: .leading, spacing: 6) {
                effectToggle("Shadow", \.shadow)
                effectToggle("Inner Stroke", \.innerStroke)
                effectToggle("Outer Stroke", \.outerStroke)
            }

            LabeledEditorSlider(label: "Opacity", value: opacityBinding, range: 0...1,
                                display: { "\(Int($0 * 100))%" })
                .frame(width: 320)

            HStack(spacing: 8) {
                Text("Tint")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                ColorPicker("", selection: tintBinding, supportsOpacity: false)
                    .labelsHidden()
                Button("Auto") { effects.wrappedValue.tint = nil }
                    .font(.system(size: 11))
                    .disabled(effects.wrappedValue.tint == nil)
                Text(effects.wrappedValue.tint == nil ? "derived from the folder color" : "")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .disabled(!hasTarget)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bindings

    /// The effects record for whichever overlay is targeted. Text effects
    /// live inside an optional `TextOverlay`, so writing through here
    /// materializes one if needed.
    private var effects: Binding<OverlayEffects> {
        Binding(
            get: {
                switch overlayTarget {
                case .graphic: return draft.graphicEffects
                case .text: return draft.text?.effects ?? OverlayEffects()
                }
            },
            set: { newValue in
                switch overlayTarget {
                case .graphic:
                    draft.graphicEffects = newValue
                case .text:
                    if draft.text == nil { draft.text = TextOverlay(text: "") }
                    draft.text?.effects = newValue
                }
            }
        )
    }

    private func effectToggle(_ label: String,
                              _ keyPath: WritableKeyPath<OverlayEffects, Bool>,
                              help: String? = nil) -> some View {
        Toggle(label, isOn: Binding(
            get: { effects.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var copy = effects.wrappedValue
                copy[keyPath: keyPath] = newValue
                effects.wrappedValue = copy
            }
        ))
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .help(help ?? label)
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { effects.wrappedValue.opacity },
                set: { var c = effects.wrappedValue; c.opacity = $0; effects.wrappedValue = c })
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { (effects.wrappedValue.tint ?? StyleColor(red: 1, green: 1, blue: 1)).swiftUIColor },
            set: { var c = effects.wrappedValue; c.tint = StyleColor(NSColor($0)); effects.wrappedValue = c }
        )
    }
}
