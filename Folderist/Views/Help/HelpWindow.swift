import AppKit
import SwiftUI

/// "Folderist Help" — the short how-to FolderMarker never shipped (its
/// single most-complained-about gap, docs/FEATURES.md §6).
///
/// Hosted in a plain `NSWindow` rather than a SwiftUI `Window` scene so the
/// Help menu command can open it directly, without routing an
/// `openWindow` action out of `Commands` into the scene graph.
enum HelpWindow {
    private static var controller: NSWindowController?

    static func show() {
        if let controller {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Folderist Help"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: HelpContentView())

        let newController = NSWindowController(window: window)
        controller = newController
        newController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HelpContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Folderist")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Give your folders an identity: a color, an icon, an emoji, an image, or your own text.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                section("Mark a folder", [
                    "Drag folders from Finder straight onto a style tile — that's the whole workflow.",
                    "Or select a tile and choose File ▸ Apply to Folders… to pick folders in a dialog.",
                    "Multiple folders at once is fine; aliases work too."
                ])

                section("Undo a folder", [
                    "Drop the folder onto the blue Restore tile (always the first tile).",
                    "Smart Restore saves whatever custom icon a folder already had, so Restore brings back the original — not just the plain macOS folder."
                ])

                section("Design a style", [
                    "Double-click a tile to open the editor — every editing control lives there.",
                    "Icons and Generic pick a symbol or an emoji; Text adds your own words; Image places a picture in one of four modes.",
                    "Each of those tabs has Remove Icon and Remove Text to clear an overlay again.",
                    "Drag inside the big preview to move the overlay, or use the Align buttons; Scale and Rotate sit below.",
                    "The color row along the bottom sets the folder color — Default Blue puts it back to the stock macOS shade."
                ])

                section("Organize", [
                    "Add New and Delete in the toolbar add and remove tiles.",
                    "Right-click a tile to apply, edit, rename, duplicate, copy/paste, export or delete it.",
                    "Drop .icns or image files on the empty space around the tiles to import them as new styles."
                ])

                section("Export", [
                    "Export ▸ Export All Icons… writes every tile into a folder you choose as .icns files.",
                    "Export ▸ Export This Icon… saves just the selected tile.",
                    "Drag a tile out to Finder to get the same .icns file — handy for Get Info."
                ])
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 560)
    }

    private func section(_ title: String, _ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").font(.system(size: 12))
                    Text(point).font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
