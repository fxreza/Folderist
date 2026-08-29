import SwiftUI

/// The rainbow strip in the middle of the toolbar (fm1/fm2/fm4): a full
/// hue spectrum you drag to recolor the selected style live.
///
/// Deliberately not a `Slider` — FolderMarker's control is the spectrum
/// itself, with a thin marker riding on top, and it must report continuously
/// during the drag so the grid tile animates under the cursor.
struct HueSlider: View {
    @Binding var hue: Double
    /// `true` while the user is dragging — the caller uses it to avoid
    /// clobbering the value from the outside mid-gesture.
    var onEditingChanged: (Bool) -> Void = { _ in }
    var isEnabled: Bool = true

    private static let spectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0)
        .map { Color(hue: $0, saturation: 0.95, brightness: 1.0) }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                marker
                    .offset(x: min(max(0, hue * width - 3), width - 6))
            }
            .frame(height: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        onEditingChanged(true)
                        hue = StyleColorMath.clamp01(value.location.x / width)
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        onEditingChanged(false)
                    }
            )
            .disabled(!isEnabled)
            .accessibilityLabel("Hue")
            .accessibilityValue("\(Int(hue * 360))°")
        }
        .frame(height: 18)
    }

    private var marker: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white)
            .frame(width: 6, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
    }
}
