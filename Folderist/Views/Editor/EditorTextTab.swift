import SwiftUI

/// The editor's **Text** tab (fm3): the text itself, the full font family /
/// face / size picker, the text color, and the embossed-vs-flat switch.
///
/// A style may have no `TextOverlay` at all, so every control writes through
/// `textBinding`, which materializes one on first use and lets "Remove Text"
/// clear it again.
struct EditorTextTab: View {
    @Binding var draft: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Text on the folder", text: textStringBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                ColorPicker("", selection: textColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .help("Text color")
            }

            // Two-state, reading and writing both `emboss` and `fill` (#18).
            EmbossFlatPicker(effects: textEffectsBinding, isEnabled: draft.text != nil)

            FontPickerView(overlay: textBinding)

            OverlayRemoveButtons(draft: $draft)
        }
    }

    // MARK: Bindings

    /// Non-optional view of `draft.text`, created on demand.
    private var textBinding: Binding<TextOverlay> {
        Binding(
            get: { draft.text ?? TextOverlay(text: "") },
            set: { draft.text = $0 }
        )
    }

    private var textStringBinding: Binding<String> {
        Binding(
            get: { draft.text?.text ?? "" },
            set: { newValue in
                if draft.text == nil { draft.text = TextOverlay(text: newValue) }
                else { draft.text?.text = newValue }
            }
        )
    }

    /// `tint == nil` means "auto" (the renderer derives a shade of the folder
    /// color); the color well always shows something, so read auto as white.
    private var textColorBinding: Binding<Color> {
        Binding(
            get: { (draft.text?.effects.tint ?? StyleColor(red: 1, green: 1, blue: 1)).swiftUIColor },
            set: { newValue in
                let styleColor = StyleColor(NSColor(newValue))
                if draft.text == nil { draft.text = TextOverlay(text: "") }
                draft.text?.effects.tint = styleColor
            }
        )
    }

    /// Non-optional view of the text overlay's effects, materializing the
    /// overlay on first write like every other control here.
    private var textEffectsBinding: Binding<OverlayEffects> {
        Binding(
            get: { draft.text?.effects ?? OverlayEffects() },
            set: { newValue in
                if draft.text == nil { draft.text = TextOverlay(text: "") }
                draft.text?.effects = newValue
            }
        )
    }
}
