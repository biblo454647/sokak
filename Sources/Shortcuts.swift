import Carbon
import AppKit

final class Shortcuts {
    private var handler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var localMonitor: Any?
    private var pressed = Set<UInt32>()
    private(set) var wiper: KeyShortcut = .wiperDefault
    private(set) var recording = false
    var action: ((UInt32) -> Void)?

    static func modifiers(_ event: NSEvent) -> UInt32 {
        let flags = event.modifierFlags
        return (flags.contains(.command) ? KeyShortcut.command : 0) | (flags.contains(.control) ? KeyShortcut.control : 0)
            | (flags.contains(.option) ? KeyShortcut.option : 0) | (flags.contains(.shift) ? KeyShortcut.shift : 0)
    }
    @discardableResult func register(wiper: KeyShortcut = .wiperDefault) -> Bool {
        self.wiper = wiper
        guard handler == nil else { return true }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.recording else { return event }
            let flags = Self.modifiers(event)
            var id: UInt32?
            if flags == (KeyShortcut.command | KeyShortcut.option | KeyShortcut.control) {
                if event.keyCode == UInt16(kVK_ANSI_S) { id = 1 }
                if event.keyCode == UInt16(kVK_ANSI_M) { id = 2 }
            }
            if flags == self.wiper.modifiers && UInt32(event.keyCode) == self.wiper.keyCode { id = 3 }
            if let id { if !event.isARepeat { self.action?(id) }; return nil }
            return event
        }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            guard id.signature == 0x534F4B4B else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Shortcuts>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed.remove(id.id) }
            else if !owner.recording && owner.pressed.insert(id.id).inserted { owner.action?(id.id) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        return status == noErr && registerBindings()
    }
    private func makeHotKey(_ key: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x534F4B4B, id: id), GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }
    private func registerBindings() -> Bool {
        var success = true
        let modifiers = KeyShortcut.command | KeyShortcut.option | KeyShortcut.control
        for (id, key, flags) in [(UInt32(1), UInt32(kVK_ANSI_S), modifiers), (UInt32(2), UInt32(kVK_ANSI_M), modifiers), (UInt32(3), wiper.keyCode, wiper.modifiers)] {
            if hotKeys[id] != nil { continue }
            if let ref = makeHotKey(key, modifiers: flags, id: id) { hotKeys[id] = ref } else { success = false }
        }
        return success
    }
    @discardableResult func setRecording(_ value: Bool) -> Bool {
        guard recording != value else { return true }
        recording = value; pressed.removeAll()
        if value {
            hotKeys.values.forEach { UnregisterEventHotKey($0) }; hotKeys.removeAll()
            return true
        }
        return registerBindings()
    }
    func replaceWiper(_ next: KeyShortcut) -> String? {
        guard next.isValid else { return "Use Command or Control with a key. Escape cancels." }
        guard !next.isSokakReserved else { return "Sokak uses that combination for pause or sound. Choose another." }
        if next == wiper && !recording && hotKeys[3] != nil { return nil }
        guard let replacement = makeHotKey(next.keyCode, modifiers: next.modifiers, id: 3) else {
            return "That shortcut is already in use. Your previous shortcut is unchanged."
        }
        // Register first: a collision must not discard the previous binding.
        if let old = hotKeys.removeValue(forKey: 3) { UnregisterEventHotKey(old) }
        wiper = next
        // Keep the successful reservation through recorder completion. Releasing
        // and registering again would let another app claim it between the two.
        hotKeys[3] = replacement
        pressed.remove(3)
        return nil
    }
    deinit {
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let handler { RemoveEventHandler(handler) }
    }
}
