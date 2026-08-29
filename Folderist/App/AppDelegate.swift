import AppKit

/// App delegate. Starts the Folderist Bar (status item + menu,
/// docs/FEATURES.md §5 / docs/PLAN.md Phase 7 — reworked per issue #15 to a
/// plain NSMenu instead of a floating palette).
///
/// NOTE: per /Users/sam/Claude/CLAUDE.md, never launch two live copies of the
/// same bundle id at once, and always launch dev builds via `open` on the
/// assembled .app bundle (see scripts/run_app.sh) — never execute the raw
/// binary directly — to avoid the status-item "blocked host" trap.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BarController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // No explicit teardown needed: the NSStatusItem is torn down with
        // the process.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The Folderist Bar (status item) keeps working after the main
        // window closes, so closing it should not quit the app.
        false
    }
}
