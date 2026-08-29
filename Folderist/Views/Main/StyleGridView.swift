import SwiftUI
import UniformTypeIdentifiers

/// The 4-column grid of large style tiles that fills the main window.
///
/// The Restore tile is always the first cell, so dropping a folder on it
/// reverts that folder's icon (Smart Restore) without hunting for a menu.
///
/// The *empty* area around the tiles is its own drop target (#12): folders
/// dropped there are imported as new styles from the icons they already
/// carry. Tiles keep their own apply-on-drop behaviour — a child drop target
/// wins over its ancestor, so a drop only reaches this view when it lands
/// between or beside the tiles.
struct StyleGridView: View {
    @EnvironmentObject private var assetStore: AssetStore
    @ObservedObject var model: MainWindowModel

    @FocusState private var gridFocused: Bool
    @State private var isImportTargeted = false

    private let columns = Array(repeating: GridItem(.fixed(150), spacing: 14), count: 4)

    private var styles: [Style] { model.selectedAsset?.styles ?? [] }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                StyleTileView(model: model, style: nil)
                ForEach(styles) { style in
                    StyleTileView(model: model, style: style)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(GridBackground())
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(nil)
            gridFocused = true
        }
        // Keyboard: Delete removes the selected style (with confirmation).
        // `onDeleteCommand` only fires for the focused view, hence the
        // focusable grid — with the focus ring suppressed, since the
        // selection ring on the tile already shows where the keys will land.
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onDeleteCommand { model.deleteSelectedStyle() }
        .onDrop(of: [.fileURL], isTargeted: $isImportTargeted) { providers in
            FolderDropResolver.resolveFiles(providers) { urls in
                model.importStylesFromIconFiles(urls)
            }
            return true
        }
        .overlay { importDropHint }
        .overlay(alignment: .center) {
            if styles.isEmpty { emptyState }
        }
    }

    /// Visual confirmation that dropping here imports rather than applies.
    @ViewBuilder
    private var importDropHint: some View {
        if isImportTargeted {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor,
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )
                .overlay(alignment: .bottom) {
                    Label("Drop .icns or image files here to import them as styles",
                          systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
                .padding(6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No styles yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Press “Add New” in the toolbar, then drag folders onto a tile. "
                 + "Dropping folders on the empty space here imports the icons they already have.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.top, 120)
        .allowsHitTesting(false)
    }
}

/// Resolves a batch of `.fileURL` drop providers to the URLs among them.
///
/// Shared by the grid (empty-area icon-file import) and the tiles
/// (apply / restore, which only want folders) so a drop behaves consistently
/// wherever it lands.
enum FolderDropResolver {
    /// Existing folders only — used by the tiles' apply/restore drop target.
    static func resolve(_ providers: [NSItemProvider],
                        completion: @escaping ([URL]) -> Void) {
        resolveURLs(providers) { urls in
            urls.filter(StyleActions.isExistingDirectory)
        } completion: { folders in
            guard !folders.isEmpty else { return }
            completion(folders)
        }
    }

    /// Existing regular files (not folders) — used by the grid's empty-area
    /// icon/image-file import; folders dropped there are ignored.
    static func resolveFiles(_ providers: [NSItemProvider],
                             completion: @escaping ([URL]) -> Void) {
        resolveURLs(providers) { urls in
            urls.filter {
                FileManager.default.fileExists(atPath: $0.path) && !StyleActions.isExistingDirectory($0)
            }
        } completion: { files in
            guard !files.isEmpty else { return }
            completion(files)
        }
    }

    private static func resolveURLs(_ providers: [NSItemProvider],
                                    filter: @escaping ([URL]) -> [URL],
                                    completion: @escaping ([URL]) -> Void) {
        let candidates = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !candidates.isEmpty else { return }
        var remaining = candidates.count
        var collected: [URL] = []
        for provider in candidates {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { collected.append(url) }
                    remaining -= 1
                    guard remaining == 0 else { return }
                    completion(filter(collected))
                }
            }
        }
    }
}

/// The backdrop behind the grid — the same semantic background as the
/// editor sheet's `EditorBackground` (`.windowBackgroundColor`, white in
/// light mode), so the main window and the editor read as one consistent
/// surface in both appearances instead of the grid's old grey wash.
struct GridBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}
