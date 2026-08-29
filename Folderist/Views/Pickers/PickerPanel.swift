import SwiftUI

/// Shared floating-panel chrome for the Symbol / Emoji / Font pickers,
/// matching FolderMarker's dark "Symbols" panel look
/// (docs/research/ui-notes.md "Floating panels" / fm1.jpg): a small title
/// bar, an optional live search field, and a dark, blurred content area.
///
/// Usage:
/// ```swift
/// PickerPanel(title: "Symbols", searchText: $query) {
///     ScrollView { /* grid */ }
/// }
/// ```
struct PickerPanel<Content: View>: View {
    var title: String
    @Binding var searchText: String
    var searchPlaceholder: String = "Search"
    /// Hide the built-in search field when a picker wants to place its own
    /// (e.g. alongside a source toggle) — the panel still supplies the frame.
    var showsSearch: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsSearch {
                PickerSearchField(text: $searchText, placeholder: searchPlaceholder)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                PickerDivider()
            }
            content()
        }
        .background(PickerPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
    }
}

/// The material fill used behind every picker panel. Semantic, so the panels
/// follow the app's Appearance setting instead of forcing dark (#7).
struct PickerPanelBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

/// A hairline divider tuned for the dark panel background.
struct PickerDivider: View {
    var body: some View {
        Divider().opacity(0.2)
    }
}

/// Live-search text field styled to match the dark utility panels.
struct PickerSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// One square glyph/tile cell shared by the symbol and emoji grids: fixed
/// 44pt hit target, subtle hover-free dark fill, rounded corners.
struct PickerGridCell<Label: View>: View {
    var isSelected: Bool = false
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
