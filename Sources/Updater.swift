import AppKit
import Combine
import Sparkle

/// Sparkle owns download, Ed25519 verification, replacement and relaunch.
/// The feed and public key are pinned in Info.plist; no GitHub account is needed.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = false
    private var controller: SPUStandardUpdaterController!
    var beforeInstall: (() -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
    }

    func start() { controller.startUpdater() }
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { beforeInstall?() }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
}
