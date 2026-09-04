import AppKit

/// App delegate. Folderist is a regular Dock app with a single main window —
/// there is no status-bar companion, so closing the last window quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
