import SwiftUI

// MARK: - Alignment presets (#17)

/// Preset overlay placements offered by the editor's alignment buttons.
///
/// `OverlayTransform.offsetX/offsetY` are fractions of the **canvas**, added
/// to the overlay's default (centred) box, so a preset is just a number. The
/// values below are chosen so the overlay still lands inside the folder's
/// front panel — which spans x ≈ 0.06…0.94 and y ≈ 0.28…0.83 of the canvas
/// (`FolderGeometry`). The graphic's default box is roughly 0.42 canvas wide,
/// leaving ±0.22 of horizontal travel; it is nearly as tall as the panel, so
/// vertical travel is much smaller. The text box is wider still, hence its
/// smaller horizontal step.
enum OverlayAlignmentPresets {
    static func horizontal(for target: OverlayTarget) -> Double {
        switch target {
        case .graphic: return 0.22
        case .text: return 0.14
        }
    }

    static func vertical(for target: OverlayTarget) -> Double {
        switch target {
        case .graphic: return 0.10
        case .text: return 0.11
        }
    }

    /// Offsets set by dragging never land exactly on a preset, so the
    /// highlight uses a tolerance rather than equality.
    static let tolerance = 0.005
}

/// Left/Center/Right + Top/Middle/Bottom buttons for whichever overlay the
/// editor's Graphic | Text selector currently targets (#17).
///
/// These only write `offsetX` / `offsetY`; dragging in the preview or moving
/// the sliders afterwards overrides them freely, and the highlight simply
/// stops matching.
struct OverlayAlignmentControls: View {
    let target: OverlayTarget
    @Binding var transform: OverlayTransform
    var isEnabled: Bool = true

    private var hStep: Double { OverlayAlignmentPresets.horizontal(for: target) }
    private var vStep: Double { OverlayAlignmentPresets.vertical(for: target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row(label: "Align",
                items: [("Left", "arrow.left.to.line", -hStep),
                        ("Center", "arrow.left.and.right", 0),
                        ("Right", "arrow.right.to.line", hStep)],
                current: transform.offsetX,
                set: { transform.offsetX = $0 })

            row(label: "Vertical",
                items: [("Top", "arrow.up.to.line", -vStep),
                        ("Middle", "arrow.up.and.down", 0),
                        ("Bottom", "arrow.down.to.line", vStep)],
                current: transform.offsetY,
                set: { transform.offsetY = $0 })
        }
        .disabled(!isEnabled)
    }

    private func row(label: String,
                     items: [(title: String, symbol: String, value: Double)],
                     current: Double,
                     set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            ForEach(items, id: \.title) { item in
                let isCurrent = abs(current - item.value) < OverlayAlignmentPresets.tolerance
                Button {
                    set(item.value)
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 16)
                }
                .buttonStyle(.bordered)
                .tint(isCurrent ? Color.accentColor : Color.secondary)
                .help(item.title)
                .accessibilityLabel("\(label) \(item.title)")
            }
        }
    }
}

// MARK: - Emboss / Flat (#18)

/// The two-state Embossed ⇄ Flat control.
///
/// `OverlayEffects` carries `emboss` and `fill` as two independent booleans,
/// which is what made the old picker look permanently stuck on "Embossed":
/// the two flags could disagree, and the segment was rendered from `emboss`
/// alone while the writes did not keep them exclusive. This control owns both
/// flags — Flat means `emboss = false, fill = true`, Embossed means
/// `emboss = true, fill = false` — so the highlighted segment always reflects
/// the state the renderer actually sees.
struct EmbossFlatPicker: View {
    @Binding var effects: OverlayEffects
    var isEnabled: Bool = true

    enum Mode: Hashable { case emboss, flat }

    /// `fill` wins when the two flags disagree (a flat overlay that also has
    /// `emboss` set still draws flat), so the readout can never lie.
    private var mode: Mode {
        if effects.fill { return .flat }
        return effects.emboss ? .emboss : .flat
    }

    var body: some View {
        Picker("", selection: Binding(get: { mode }, set: apply)) {
            Text("Embossed").tag(Mode.emboss)
            Text("Flat").tag(Mode.flat)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
        .disabled(!isEnabled)
    }

    private func apply(_ newMode: Mode) {
        var updated = effects
        updated.emboss = (newMode == .emboss)
        updated.fill = (newMode == .flat)
        effects = updated
    }
}

// MARK: - Per-tab remove actions (#16)

/// "Remove Icon" / "Remove Text", shown on every content tab so clearing an
/// overlay never means hunting for the one tab that happens to own it (#16).
struct OverlayRemoveButtons: View {
    @Binding var draft: Style

    var body: some View {
        HStack(spacing: 8) {
            Button("Remove Icon") { draft.graphic = nil }
                .disabled(draft.graphic == nil)
                .help("Clear the symbol, emoji or image on this style")
            Button("Remove Text") { draft.text = nil }
                .disabled(draft.text == nil)
                .help("Clear the text on this style")
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}
