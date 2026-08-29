import AppKit
import SwiftUI

/// The toolbar strip across the top of the main window.
///
/// Deliberately tiny (#13): user testing found the old strip — a rainbow hue
/// slider plus nine unlabelled glyphs — unreadable, and every one of those
/// glyphs duplicated something the double-click editor already does. What is
/// left is the three actions that have nowhere else to live, each with an
/// icon *and* a text label:
///
///     [ Export ▾ ]                        [ + Add New ]  [ − Delete ]
struct ToolbarStrip: View {
    @ObservedObject var model: MainWindowModel

    private var hasSelection: Bool { model.selectedStyle != nil }

    var body: some View {
        HStack(spacing: 8) {
            exportMenu
            Spacer(minLength: 12)
            Button {
                model.addStyle()
            } label: {
                Label("Add New", systemImage: "plus")
            }
            .help("Add a new style to the grid")

            Button(role: .destructive) {
                model.deleteSelectedStyle()
            } label: {
                Label("Delete", systemImage: "minus")
            }
            .disabled(!hasSelection)
            .help("Delete the selected style")
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// One Export control, holding exactly the two icon exports the app now
    /// offers — both `.icns` (#11).
    private var exportMenu: some View {
        Menu {
            Button("Export All Icons…") { model.exportAllStyles() }
                .disabled(!model.hasStyles)
            Button("Export This Icon…") { model.exportSelectedStyle() }
                .disabled(!hasSelection)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Export folder icons as .icns files")
    }
}
