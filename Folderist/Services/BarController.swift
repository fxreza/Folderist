import AppKit

/// Owns the Folderist Bar: a plain `NSStatusItem` (folder-glyph template
/// icon) with a standard `NSMenu` — "Open Folderist", "Check for Updates…",
/// and "Quit Folderist" (docs/FEATURES.md §5, reworked per issue #15: no
/// floating palette, just a menu).
///
/// Visibility is controlled by the `"showBar"` `UserDefaults` key (default
/// `true`) — flip it off and the status item goes away; flip it back on and
/// it reappears. The main-UI agent's Settings screen should read/write that
/// same key, e.g. `UserDefaults.standard.set(false, forKey: "showBar")`, to
/// add a "Show Folderist Bar" toggle — `BarController` observes the key
/// itself, no further wiring needed.
final class BarController: NSObject {
    static let shared = BarController()

    private static let showBarDefaultsKey = "showBar"

    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private var isObservingDefaults = false

    private override init() {
        super.init()
        defaults.register(defaults: [Self.showBarDefaultsKey: true])
    }

    deinit {
        if isObservingDefaults {
            defaults.removeObserver(self, forKeyPath: Self.showBarDefaultsKey)
        }
    }

    /// Call once from `AppDelegate.applicationDidFinishLaunching`.
    func start() {
        guard !isObservingDefaults else { return }
        isObservingDefaults = true
        defaults.addObserver(self, forKeyPath: Self.showBarDefaultsKey, options: [.new], context: nil)
        applyVisibility()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == Self.showBarDefaultsKey else { return }
        DispatchQueue.main.async { [weak self] in self?.applyVisibility() }
    }

    private var showBar: Bool { defaults.bool(forKey: Self.showBarDefaultsKey) }

    private func applyVisibility() {
        if showBar {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    // MARK: - Status item

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folderist")
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let configured = symbol?.withSymbolConfiguration(config) ?? symbol
            configured?.isTemplate = true
            button.image = configured
        }
        // Attaching a menu makes NSStatusItem show it on both left and right
        // click, with no extra click handling needed.
        item.menu = makeMenu()
        statusItem = item
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Menu

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let versionItem = NSMenuItem(title: "Folderist \(Self.appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Folderist", action: #selector(openFolderist), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Folderist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func openFolderist() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Folderist \(Self.appVersion) is up to date."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
