import AppKit
import SwiftUI

/// Tabs across the top of the style editor (fm3): FolderMarker's
/// Icons | Effects | Generic | Text | Image; the Image tab is always visible
/// and is where a user image is added, swapped, or removed (fm5).
enum EditorTab: String, CaseIterable, Identifiable {
    case icons = "Icons"
    case effects = "Effects"
    case generic = "Generic"
    case text = "Text"
    case image = "Image"
    var id: String { rawValue }
}

/// Which overlay the transform + effects controls act on.
enum OverlayTarget: String, CaseIterable, Identifiable {
    case graphic = "Graphic"
    case text = "Text"
    var id: String { rawValue }
}

/// The style editor: a big live preview plus every control for one `Style`,
/// presented as a sheet over the grid (fm3 / fm5).
///
/// Edits are made against a working copy (`draft`) so **Cancel** genuinely
/// discards; **Ok** writes the whole style back at once through
/// `AssetStore.updateStyle`.
struct EditorSheet: View {
    @EnvironmentObject private var assetStore: AssetStore
    @ObservedObject var model: MainWindowModel
    let target: MainWindowModel.EditorTarget

    @State private var draft: Style
    @State private var tab: EditorTab
    @State private var overlayTarget: OverlayTarget = .graphic
    @State private var dragBaseline: OverlayTransform?
    @AppStorage("appearance") private var appearance: AppearanceSetting = .auto

    init(model: MainWindowModel, target: MainWindowModel.EditorTarget) {
        self.model = model
        self.target = target
        let existing = AppServices.shared.assetStore.library.assets
            .first { $0.id == target.assetID }?
            .styles.first { $0.id == target.styleID } ?? Style()
        _draft = State(initialValue: existing)
        _tab = State(initialValue: target.initialTab)
    }

    private var resources: RenderResources { AppServices.shared.renderResources }

    private var visibleTabs: [EditorTab] {
        EditorTab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.3)
            HStack(alignment: .top, spacing: 14) {
                tabContent
                    .frame(width: 446, height: 448, alignment: .top)
                previewColumn
                    .frame(width: 248)
            }
            .padding(14)
            Divider().opacity(0.3)
            EditorColorSection(fill: $draft.fill)
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 740)
        .background(EditorBackground())
        .preferredColorScheme(appearance.colorScheme)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { item in
                Button {
                    tab = item
                    if item == .text { overlayTarget = .text }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? AnyShapeStyle(Color.accentColor)
                                                     : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(tab == item ? Color.accentColor : .clear)
                        .frame(height: 2)
                }
            }
        }
        .background(Color.primary.opacity(0.04))
    }

    // MARK: Tab content

    /// Every *content* tab (Icons, Generic, Text, Image) carries the same
    /// clearly-labelled remove actions (#16); Effects has no overlay of its
    /// own to remove, so it is the one tab without them.
    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .icons:
            withRemoveActions {
                SymbolPickerView(catalogIndex: model.catalogIndex) { graphic in
                    draft.graphic = graphic
                    // Textures read as a seamless surface, not a small centered glyph, so
                    // scale the default box up to cover more of the front panel. The overlay
                    // box is square while the front panel is wider than it is tall, and
                    // bundled-symbol overlays aren't clipped to the folder silhouette, so this
                    // is tuned to fill the panel's full height without spilling past the
                    // folder's own top/bottom edges onto the background.
                    if case .bundledSymbol("heropatterns", _) = graphic {
                        draft.graphicTransform.scale = 1.4
                    }
                }
            }
        case .generic:
            withRemoveActions {
                EmojiPickerView(catalogIndex: model.catalogIndex) { emoji in
                    draft.graphic = .emoji(emoji)
                }
            }
        case .text:
            // Text and Image place the same remove row inline, where their
            // own controls already sit.
            EditorTextTab(draft: $draft)
        case .image:
            EditorImageTab(draft: $draft)
        case .effects:
            EditorEffectsTab(draft: $draft, overlayTarget: $overlayTarget)
        }
    }

    private func withRemoveActions<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
            OverlayRemoveButtons(draft: $draft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Preview + transforms

    private var previewColumn: some View {
        VStack(spacing: 10) {
            preview
            transformControls
            Spacer(minLength: 0)
        }
    }

    private var preview: some View {
        Image(nsImage: StyleIconCache.shared.previewIcon(for: draft, resources: resources))
            .resizable()
            .interpolation(.high)
            .frame(width: 224, height: 224)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .gesture(previewDrag)
            .help("Drag to move the \(overlayTarget.rawValue.lowercased()) overlay")
    }

    /// Dragging in the preview moves the selected overlay. The renderer's
    /// offsets are fractions of the canvas, so the pixel delta is divided by
    /// the preview's side length — the overlay tracks the cursor 1:1.
    private var previewDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragBaseline == nil { dragBaseline = currentTransform }
                guard let base = dragBaseline else { return }
                var t = base
                t.offsetX = base.offsetX + Double(value.translation.width / 224)
                t.offsetY = base.offsetY + Double(value.translation.height / 224)
                setTransform(t)
            }
            .onEnded { _ in dragBaseline = nil }
    }

    private var transformControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $overlayTarget) {
                ForEach(OverlayTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Alignment presets for the targeted overlay (#17). They live in
            // the preview column rather than inside one tab, so they are
            // reachable from every tab — and right next to the drag surface
            // and sliders that override them.
            OverlayAlignmentControls(target: overlayTarget,
                                     transform: transformBinding,
                                     isEnabled: hasTargetedOverlay)

            LabeledEditorSlider(label: "Scale", value: scaleBinding, range: 0.2...3.0,
                                display: { String(format: "%.2f×", $0) })
            LabeledEditorSlider(label: "Rotate", value: rotationBinding, range: -180...180,
                                display: { "\(Int($0))°" })

            Button("Reset Position") { setTransform(OverlayTransform()) }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    // MARK: Transform plumbing

    /// Whether the overlay the Graphic | Text selector points at actually
    /// exists — placement controls have nothing to move otherwise.
    private var hasTargetedOverlay: Bool {
        switch overlayTarget {
        case .graphic: return draft.graphic != nil
        case .text: return draft.text != nil
        }
    }

    private var currentTransform: OverlayTransform {
        switch overlayTarget {
        case .graphic: return draft.graphicTransform
        case .text: return draft.text?.transform ?? OverlayTransform()
        }
    }

    private func setTransform(_ t: OverlayTransform) {
        switch overlayTarget {
        case .graphic:
            draft.graphicTransform = t
        case .text:
            if draft.text == nil { draft.text = TextOverlay(text: "") }
            draft.text?.transform = t
        }
    }

    /// Read/write view of the targeted overlay's whole transform, for
    /// controls that set more than one field.
    private var transformBinding: Binding<OverlayTransform> {
        Binding(get: { currentTransform }, set: { setTransform($0) })
    }

    private var scaleBinding: Binding<Double> {
        Binding(get: { currentTransform.scale },
                set: { var t = currentTransform; t.scale = $0; setTransform(t) })
    }

    private var rotationBinding: Binding<Double> {
        Binding(get: { currentTransform.rotationDegrees },
                set: { var t = currentTransform; t.rotationDegrees = $0; setTransform(t) })
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            TextField("Style name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 180)

            Spacer()

            Button("Cancel") { model.editing = nil }
                .keyboardShortcut(.cancelAction)
            Button("Ok") { commit() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func commit() {
        // An empty text overlay would otherwise linger as a no-op that still
        // changes the graphic's layout box (`textBox(withGraphic:)`).
        if draft.text?.text.trimmingCharacters(in: .whitespaces).isEmpty == true {
            draft.text = nil
        }
        do {
            try assetStore.updateStyle(draft, in: target.assetID)
        } catch {
            StyleActions.report(error, title: "Couldn't save the style")
        }
        model.editing = nil
    }
}

// MARK: - Shared editor chrome

/// A labelled slider with a fixed-width numeric readout — the editor's
/// standard control, used for scale, rotation, opacity and gradient angle.
struct LabeledEditorSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var display: (Double) -> String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Slider(value: $value, in: range)
            Text(display(value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

/// The editor's backdrop, matched to the picker panels. Semantic rather than
/// a fixed near-black so the sheet is legible in light mode too (#7).
struct EditorBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Rectangle().fill(.ultraThinMaterial).opacity(0.5)
        }
    }
}
