import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> ShortcutRecordButton {
        let button = ShortcutRecordButton()
        button.model = model
        return button
    }
    func updateNSView(_ button: ShortcutRecordButton, context: Context) {
        button.title = model.recordingWiperShortcut ? "Press shortcut…" : model.preferences.wiperShortcut.display
        button.setAccessibilityLabel("Wiper shortcut")
        button.setAccessibilityValue(button.title)
        button.toolTip = "Click and press a combination with Command or Control. Escape cancels."
        if !model.recordingWiperShortcut { button.endCapture() }
    }
}

final class ShortcutRecordButton: NSButton {
    weak var model: AppModel?
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        target = self; action = #selector(beginCapture)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func beginCapture() {
        guard let model else { return }
        if model.recordingWiperShortcut { cancel(); return }
        model.shortcutError = nil; model.recordingWiperShortcut = true
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model?.recordingWiperShortcut == true, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { self.cancel(); return nil }
            if event.keyCode == 48 && Shortcuts.modifiers(event) == 0 { self.cancel(); return event }
            if !event.isARepeat { self.record(event) }
            return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.cancel() }
    }
    private func record(_ event: NSEvent) {
        let named: [UInt16: String] = [36:"↩",48:"⇥",49:"Space",51:"⌫",76:"⌤",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",115:"↖",119:"↘",116:"⇞",121:"⇟",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
        let label = named[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        model?.setWiperShortcut(KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: Shortcuts.modifiers(event), keyLabel: label))
    }
    func endCapture() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
    private func cancel() {
        if model?.recordingWiperShortcut == true { model?.shortcutError = nil }
        model?.recordingWiperShortcut = false
        endCapture()
    }
    override func resignFirstResponder() -> Bool { cancel(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancel() }
        super.viewWillMove(toWindow: newWindow)
    }
    deinit { endCapture() }
}
