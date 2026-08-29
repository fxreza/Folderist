import SwiftUI

/// Which glyph source the symbol picker is currently browsing.
enum SymbolSource: String, CaseIterable, Identifiable {
    case all = "All Symbols"
    case sfSymbols = "SF Symbols"
    case lucide = "Lucide"
    case phosphor = "Phosphor"
    case material = "Material"
    case remix = "Remix"
    case bootstrap = "Bootstrap"
    case heroicons = "Heroicons"
    case textures = "Textures"
    var id: String { rawValue }

    /// The `CatalogIndex`/`CatalogLookup` catalog name this source resolves glyphs from.
    /// `nil` for `.sfSymbols` (not a bundled catalog) and `.all` (spans every catalog).
    var catalog: String? {
        switch self {
        case .all: return nil
        case .sfSymbols: return nil
        case .lucide: return "lucide"
        case .phosphor: return "phosphor"
        case .material: return "material"
        case .remix: return "remix"
        case .bootstrap: return "bootstrap"
        case .heroicons: return "heroicons"
        case .textures: return "heropatterns"
        }
    }
}

/// Searchable grid of monochrome glyphs for a style's graphic overlay,
/// switchable between system SF Symbols (`SFSymbolCatalog`, since Apple has
/// no public API to enumerate all ~6,000), the bundled icon packs
/// (Lucide/Phosphor/Material/Remix/Bootstrap/Heroicons), and the bundled
/// seamless-pattern textures (heropatterns) — all indexed by `CatalogIndex`.
/// Matches FolderMarker's dark "Symbols" floating panel (docs/research/ui-notes.md
/// "Floating panels", fm1.jpg).
///
/// With seven glyph sources, a segmented control no longer fits the panel's
/// width, so the source switch is a compact popup menu instead.
///
/// Self-contained: construct with just a completion handler for a quick
/// drop-in, or pass a shared `CatalogIndex` to reuse one already loaded
/// elsewhere in the app.
struct SymbolPickerView: View {
    let catalogIndex: CatalogIndex
    var onPick: (GraphicOverlay) -> Void

    // Always starts on "All Symbols" — a plain `@State` (never `@AppStorage`)
    // so the picker never remembers the last-used source across openings.
    @State private var source: SymbolSource = .all
    @State private var searchText: String = ""

    init(catalogIndex: CatalogIndex = CatalogIndex(), onPick: @escaping (GraphicOverlay) -> Void) {
        self.catalogIndex = catalogIndex
        self.onPick = onPick
    }

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 6)]

    var body: some View {
        PickerPanel(title: "Symbols", searchText: $searchText,
                    searchPlaceholder: source == .textures ? "Search textures" : "Search symbols") {
            VStack(spacing: 0) {
                sourcePicker
                PickerDivider()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        gridContent
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 280, height: 360)
    }

    private var sourcePicker: some View {
        HStack {
            Picker("", selection: $source) {
                ForEach(SymbolSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // `.all` renders SF Symbols followed by every bundled catalog (textures
    // last), so the two `ForEach`es below simply run back to back — the
    // combined ~9000 entries stay cheap because `LazyVGrid` only builds cells
    // near the visible area, and `PreviewGlyph`/`PreviewGlyphLoader` cache
    // each decoded glyph on first appearance, so scrolling never re-decodes.
    @ViewBuilder
    private var gridContent: some View {
        if source == .sfSymbols || source == .all {
            sfSymbolCells
        }
        if source != .sfSymbols {
            catalogCells
        }
    }

    private var sfSymbolCells: some View {
        ForEach(filteredSFSymbols, id: \.self) { name in
            PickerGridCell {
                onPick(.sfSymbol(name: name))
            } label: {
                Image(systemName: name)
                    .font(.system(size: 18))
            }
            .help(name)
        }
    }

    private var catalogCells: some View {
        ForEach(filteredEntries, id: \.url) { entry in
            PickerGridCell {
                onPick(.bundledSymbol(catalog: entry.catalog, name: entry.name))
            } label: {
                PreviewGlyph(url: entry.url).frame(width: 22, height: 22)
            }
            .help(entry.displayName)
        }
    }

    private var filteredSFSymbols: [String] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SFSymbolCatalog.all }
        return SFSymbolCatalog.all.filter { $0.contains(q) }
    }

    private var filteredEntries: [CatalogIndex.IconEntry] {
        switch source {
        case .all:
            return catalogIndex.searchAllIcons(query: searchText)
        case .textures:
            return catalogIndex.searchTextures(query: searchText)
        case .sfSymbols:
            return []
        default:
            guard let catalog = source.catalog else { return [] }
            return catalogIndex.searchIcons(catalog: catalog, query: searchText)
        }
    }
}
