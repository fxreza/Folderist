import SwiftUI

/// How the app picks its light/dark appearance (#7). Stored in
/// `@AppStorage("appearance")` and applied at the top of every window; the
/// hard-coded `.preferredColorScheme(.dark)` this replaces made the whole app
/// ignore the system setting.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` = follow the system, which is what SwiftUI's
    /// `preferredColorScheme` treats as "don't override".
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The main window: the toolbar strip on top and the style grid below, with
/// the style editor presented as a sheet.
struct MainWindowView: View {
    @EnvironmentObject private var assetStore: AssetStore
    @ObservedObject private var model = MainWindowModel.shared
    @AppStorage("appearance") private var appearance: AppearanceSetting = .auto

    var body: some View {
        VStack(spacing: 0) {
            ToolbarStrip(model: model)
            StyleGridView(model: model)
        }
        .background(GridBackground())
        .sheet(item: Binding(get: { model.editing }, set: { model.editing = $0 })) { target in
            EditorSheet(model: model, target: target)
                .environmentObject(assetStore)
        }
        .onAppear {
            if model.selectedStyleID == nil {
                model.selectedStyleID = model.selectedAsset?.styles.first?.id
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}

#if DEBUG
/// Debug-only preview harness. `swift build` compiles this target as an app,
/// so this exists purely so the file can be opened in Xcode's canvas once the
/// project is opened there — it is never referenced at runtime.
struct MainWindowView_Previews: PreviewProvider {
    static var previews: some View {
        MainWindowView()
            .environmentObject(AppServices.shared.assetStore)
            .frame(width: 820, height: 660)
    }
}
#endif
