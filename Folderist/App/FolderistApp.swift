import SwiftUI

/// App entry point for Folderist.
///
/// A single main window sized as a compact utility window: the toolbar strip
/// on top and the 4-column style grid below.
@main
struct FolderistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearance") private var appearance: AppearanceSetting = .auto

    init() {
        // Drag-out writes .icns files into a temp scratch area; sweep out
        // anything a previous run left behind (#20).
        StyleActions.cleanUpOldDragFiles()
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(AppServices.shared.assetStore)
                .frame(minWidth: 700, minHeight: 520)
        }
        .defaultSize(width: 820, height: 660)
        .commands { FolderistCommands() }
    }
}

/// The menu bar: File / Edit additions / View / Help.
///
/// Every command drives `MainWindowModel.shared` — menu commands live outside
/// the window's view tree and cannot reach a `@StateObject` inside it, which
/// is why that model is shared (see its doc comment).
struct FolderistCommands: Commands {
    @ObservedObject private var model = MainWindowModel.shared
    @AppStorage("showBar") private var showBar: Bool = true
    @AppStorage("appearance") private var appearance: AppearanceSetting = .auto

    var body: some Commands {
        // File. Mirrors the toolbar exactly: apply, then the two .icns
        // exports (#11). Asset documents and PNG/iconset exports are gone.
        CommandGroup(replacing: .newItem) {
            Button("Apply to Folders…") { model.applySelectedStyleToChosenFolders() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Divider()
            Button("Export All Icons…") { model.exportAllStyles() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export This Icon…") { model.exportSelectedStyle() }
                .keyboardShortcut("e", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Style") { model.copySelectedStyle() }
            Button("Paste Style") { model.pasteStyle() }
            Button("Duplicate Style") { model.duplicateSelectedStyle() }
                .keyboardShortcut("d", modifiers: .command)
            // Deliberately no Return shortcut: a bare-Return key equivalent
            // would out-rank every text field in the app.
            Button("Rename Style") { model.renamingStyleID = model.selectedStyleID }
            Button("Delete Style") { model.deleteSelectedStyle() }
        }

        CommandGroup(after: .toolbar) {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show Folderist Bar", isOn: $showBar)
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Folderist Help") { HelpWindow.show() }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
