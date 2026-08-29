import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One large folder tile in the main grid: the rendered style, a caption
/// underneath, a selection ring, a Finder-folder drop target, and a drag
/// *source* that hands out a rendered `.icns`.
///
/// The three hover buttons that used to float above a tile (apply / edit /
/// duplicate) are gone (#14) — they appeared on hover, covered the artwork
/// and duplicated the context menu. What is left is: click to select,
/// double-click to edit, right-click for everything else, drop folders on to
/// apply, drag out to export.
struct StyleTileView: View {
    @EnvironmentObject private var assetStore: AssetStore
    @ObservedObject var model: MainWindowModel

    /// `nil` marks this as the Restore tile (always first in the grid).
    let style: Style?

    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var isFlashing = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private var isRestoreTile: Bool { style == nil }
    private var displayStyle: Style { style ?? Self.restoreStyle }
    private var isSelected: Bool { style.map { $0.id == model.selectedStyleID } ?? false }
    private var isRenaming: Bool { style.map { $0.id == model.renamingStyleID } ?? false }

    private var caption: String {
        if isRestoreTile { return "Restore" }
        return style.map { model.caption(for: $0) } ?? ""
    }

    private var resources: RenderResources { AppServices.shared.renderResources }

    var body: some View {
        VStack(spacing: 4) {
            tile
            captionView
        }
        .frame(width: 150)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { if !isRestoreTile { openEditor() } }
        .onTapGesture { if let style { model.select(style.id) } }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            FolderDropResolver.resolve(providers) { urls in handleDrop(urls) }
            return true
        }
        .contextMenu { contextMenu }
    }

    // MARK: Pieces

    private var tile: some View {
        Image(nsImage: StyleIconCache.shared.gridIcon(for: displayStyle, resources: resources))
            .resizable()
            .interpolation(.high)
            .frame(width: 112, height: 112)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isFlashing ? 0.45 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ringColor, lineWidth: isTargeted ? 2 : 1.5)
            )
            .modifier(TileDragModifier(style: style, name: caption))
    }

    /// Selection/hover fills use `Color.primary`, so they darken a light
    /// window and lighten a dark one instead of always washing white (#7).
    private var backgroundFill: Color {
        if isTargeted { return Color.accentColor.opacity(0.30) }
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var ringColor: Color {
        if isTargeted { return .accentColor }
        if isSelected { return Color.accentColor.opacity(0.9) }
        return .clear
    }

    @ViewBuilder
    private var captionView: some View {
        if isRenaming, let style {
            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .focused($renameFieldFocused)
                .frame(width: 120)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .onSubmit { commitRename(style) }
                .onAppear {
                    renameText = style.name
                    renameFieldFocused = true
                }
                .onChange(of: renameFieldFocused) { _, focused in
                    if !focused { commitRename(style) }
                }
        } else {
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 132)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let style {
            Button("Apply to Folders…") {
                let urls = StyleActions.chooseFolders()
                guard !urls.isEmpty else { return }
                StyleActions.apply(style: style, to: urls)
            }
            Button("Edit…") { openEditor() }
            Button("Rename") {
                model.select(style.id)
                model.renamingStyleID = style.id
            }
            Button("Duplicate") {
                model.select(style.id)
                model.duplicateSelectedStyle()
            }
            Divider()
            Button("Copy Style") { model.styleClipboard = style }
            Button("Paste Style") { model.pasteStyle() }
                .disabled(model.styleClipboard == nil)
            Divider()
            Button("Export This Icon…") {
                StyleActions.exportIcon(style: style, suggestedName: model.caption(for: style))
            }
            Divider()
            Button("Delete") {
                model.select(style.id)
                model.deleteSelectedStyle()
            }
        } else {
            Button("Restore Folders…") {
                let urls = StyleActions.chooseFolders(prompt: "Restore")
                guard !urls.isEmpty else { return }
                StyleActions.restore(urls: urls)
            }
        }
    }

    // MARK: Actions

    private func openEditor() {
        guard let style else { return }
        model.openEditor(styleID: style.id)
    }

    private func commitRename(_ style: Style) {
        guard model.renamingStyleID == style.id else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let assetID = model.selectedAssetID {
            try? assetStore.renameStyle(style.id, in: assetID, to: trimmed)
        }
        model.renamingStyleID = nil
    }

    private func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let style {
            StyleActions.apply(style: style, to: urls)
        } else {
            StyleActions.restore(urls: urls)
        }
        flash()
    }

    private func flash() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.easeOut(duration: 0.06)) { isFlashing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeIn(duration: 0.2)) { isFlashing = false }
        }
    }

    /// The Restore tile, drawn through the same renderer as every other tile
    /// so it sits in the grid without special-case artwork.
    static let restoreStyle = Style(
        name: "Restore",
        fill: .solid(StyleColor(red: 0.259, green: 0.522, blue: 0.957)),
        graphic: .sfSymbol(name: "arrow.uturn.backward")
    )
}

// MARK: - Drag out

/// Makes a style tile a drag *source*. Dragging it out writes a compiled
/// `.icns` to a temp directory and hands Finder that file (#20) — it used to
/// produce a PNG, which Finder will not accept as a folder icon.
///
/// A view modifier rather than an inline `.onDrag` because the Restore tile
/// has nothing to export and must stay un-draggable.
private struct TileDragModifier: ViewModifier {
    let style: Style?
    let name: String

    func body(content: Content) -> some View {
        if let style {
            content.onDrag {
                guard let url = StyleActions.temporaryICNS(for: style, name: name),
                      let provider = NSItemProvider(contentsOf: url) else {
                    return NSItemProvider()
                }
                provider.suggestedName = url.lastPathComponent
                return provider
            }
        } else {
            content
        }
    }
}
