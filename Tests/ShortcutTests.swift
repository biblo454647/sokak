import AppKit
import Carbon

@main struct ShortcutTests {
    static func main() {
        _ = NSApplication.shared
        let shortcuts = Shortcuts()
        precondition(shortcuts.register(), "Run this isolated test with other Sokak copies closed")
        let previous = shortcuts.wiper
        let next = KeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: KeyShortcut.wiperDefault.modifiers, keyLabel: "J")
        var blocker: EventHotKeyRef?
        precondition(RegisterEventHotKey(next.keyCode, next.modifiers, EventHotKeyID(signature: 0x54455354, id: 91), GetApplicationEventTarget(), 0, &blocker) == noErr)
        precondition(shortcuts.replaceWiper(next) != nil && shortcuts.wiper == previous,
                     "A collision must preserve the previous binding")
        UnregisterEventHotKey(blocker!)
        precondition(shortcuts.replaceWiper(next) == nil && shortcuts.wiper == next)
        precondition(shortcuts.setRecording(true) && shortcuts.recording)
        precondition(shortcuts.replaceWiper(.wiperDefault) == nil)
        precondition(shortcuts.setRecording(false) && !shortcuts.recording && shortcuts.wiper == .wiperDefault)
        let reserved = KeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: previous.modifiers, keyLabel: "S")
        precondition(shortcuts.replaceWiper(reserved) != nil && shortcuts.wiper == previous)
        precondition(shortcuts.replaceWiper(KeyShortcut(keyCode: 13, modifiers: 0, keyLabel: "W")) != nil)
        print("Passed: native hot-key registration, collision rollback, replacement, recorder suspension/resume and reserved-key rejection.")
    }
}
