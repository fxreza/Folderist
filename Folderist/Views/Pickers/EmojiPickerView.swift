import SwiftUI

/// Searchable emoji grid for a style's graphic overlay. Emoji render as
/// plain text glyphs (the system emoji font), so no image assets are
/// required for display — `CatalogIndex`'s bundled Twemoji catalog only
/// supplies the character list and search keywords.
///
/// Falls back to `EmojiFallbackCatalog` (a built-in list of ~200 common
/// emoji) when the catalog's `emoji` array is empty, e.g. because the
/// AssetPacks resource directory isn't wired into this build yet.
struct EmojiPickerView: View {
    let catalogIndex: CatalogIndex
    var onPick: (String) -> Void

    @State private var searchText: String = ""

    init(catalogIndex: CatalogIndex = CatalogIndex(), onPick: @escaping (String) -> Void) {
        self.catalogIndex = catalogIndex
        self.onPick = onPick
    }

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 4)]

    var body: some View {
        PickerPanel(title: "Emoji", searchText: $searchText, searchPlaceholder: "Search emoji") {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(filteredEmoji.enumerated()), id: \.offset) { _, character in
                        PickerGridCell {
                            onPick(character)
                        } label: {
                            Text(character).font(.system(size: 22))
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 280, height: 360)
    }

    private var filteredEmoji: [String] {
        guard !catalogIndex.emoji.isEmpty else {
            return EmojiPickerView.filteredFallback(query: searchText)
        }
        return catalogIndex.searchEmoji(searchText).map { $0.character }
    }

    private static func filteredFallback(query: String) -> [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return EmojiFallbackCatalog.all.map { $0.character } }
        return EmojiFallbackCatalog.all
            .filter { entry in entry.keywords.contains { $0.contains(q) } }
            .map { $0.character }
    }
}
