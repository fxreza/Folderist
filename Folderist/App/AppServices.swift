import AppKit

/// Shared instances of the app's core services, so every part of the app
/// operates on the same data instead of each constructing its own
/// `AssetStore`.
///
/// Integration notes for the main-UI agent:
/// - `AppServices.shared.assetStore` is the one `AssetStore` for the whole
///   app. `FolderistApp.swift` already injects it as an `@EnvironmentObject`
///   for the main window (`.environmentObject(AppServices.shared.assetStore)`)
///   — read/write through that instance rather than constructing another one,
///   or the views will drift out of sync.
/// - `renderResources` is a single `BundleRenderResources` pointed at the
///   same on-disk images directory `assetStore` writes `GraphicOverlay.image`
///   files into. Reuse it (or build one the same way) whenever calling
///   `FolderIconRenderer` so user-imported images resolve correctly.
/// - `iconApplier` / `tagService` are stateless — `IconApplier` and
///   `TagService` are enums of static functions with no instance state — the
///   properties just give one place to spell them; calling the types
///   directly (`IconApplier.apply(...)`) is equally correct.
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let assetStore: AssetStore
    let smartRestore: SmartRestoreStore
    let renderResources: RenderResources
    let iconApplier: IconApplier.Type = IconApplier.self
    let tagService: TagService.Type = TagService.self

    private init() {
        let store = AssetStore()
        // AssetStore keeps its images directory private; it's always
        // `<defaultRootDirectory>/images`, so reconstruct it here rather
        // than widening AssetStore's API for this one need.
        let imagesDirectory = AssetStore.defaultRootDirectory()
            .appendingPathComponent("images", isDirectory: true)
        self.assetStore = store
        self.smartRestore = SmartRestoreStore()
        self.renderResources = BundleRenderResources(userImagesDirectory: imagesDirectory)
    }
}
