import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel(
        defaults: CommandLine.arguments.contains("--self-test") ? UserDefaults(suiteName: "com.sokakapp.Sokak.selftest")! : .standard,
        includePersonalPhotos: !CommandLine.arguments.contains("--self-test")
    )
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var overlay: OverlayController!
    private let sound = Ambience()
    private let shortcuts = Shortcuts()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            DispatchQueue.main.async {
                do { try QualityCheck.run(output: url, model: self.model); exit(0) }
                catch { fputs("Self-test failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        // A second launch should reveal the existing menu rather than create another overlay.
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.sokakapp.Sokak").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        overlay = OverlayController(model: model)
        overlay.onRainContacts = { [weak self] contacts in self?.sound.playRainContacts(contacts) }
        overlay.onWiperStart = { [weak self] in self?.sound.playWiper() }
        model.onWipe = { [weak self] in self?.overlay.wipeGlass() }
        model.onWiperShortcutChange = { [weak self] shortcut in self?.shortcuts.replaceWiper(shortcut) }
        model.onRecordingShortcutChange = { [weak self] recording in
            guard let self else { return }
            if !self.shortcuts.setRecording(recording) {
                self.model.shortcutError = "A shortcut is unavailable. Choose another combination; menu controls still work."
            }
        }
        model.updater.beforeInstall = { [weak model] in model?.stop() }
        model.updater.start()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let height = min(CGFloat(730), (NSScreen.main?.visibleFrame.height ?? 900) - 65)
        popover.contentSize = NSSize(width: 390, height: height)
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model, height: height))
        model.closePopover = { [weak self] in self?.popover.performClose(nil) }
        model.onChange = { [weak self] in self?.synchronize() }
        model.onRunningChange = { [weak self] in self?.synchronize() }
        sound.onError = { [weak model] message in model?.error = message }
        shortcuts.action = { [weak model] id in
            if id == 1 { model?.toggle() } else if id == 2 { model?.preferences.sound.toggle() } else if id == 3 { model?.wipeGlass() }
        }
        if !shortcuts.register(wiper: model.preferences.wiperShortcut) { model.shortcutError = "A keyboard shortcut is in use by another app. You can use the menu controls or choose another wiper shortcut." }
        synchronize()
        if !UserDefaults.standard.bool(forKey: "has-opened-v1") || CommandLine.arguments.contains("--show") {
            UserDefaults.standard.set(true, forKey: "has-opened-v1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopover() }
        }
    }
    private func synchronize() {
        overlay.update()
        if !popover.isShown { overlay.focusImmersive() }
        sound.update(running: model.running, preferences: model.preferences)
        let image = NSImage(systemSymbolName: model.running ? model.preferences.weather.symbol + (model.preferences.weather == .rain ? ".fill" : "") : "cloud", accessibilityDescription: "Sokak — \(model.running ? "weather running" : "paused")")
        image?.isTemplate = true
        status.button?.image = image
        status.button?.toolTip = "Sokak · \(model.running ? model.preferences.weather.title : "Paused") · ⌃⌥⌘S"
    }
    func popoverDidClose(_ notification: Notification) { model.recordingWiperShortcut = false; overlay.focusImmersive() }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { model.toggle(); return }
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    private func showPopover() {
        guard let button = status.button else { return }
        model.refreshDisplays()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPopover(); return true }
    func applicationWillTerminate(_ notification: Notification) { overlay?.stop(); sound.stopImmediately() }
}

@main
struct SokakApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
