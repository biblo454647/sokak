import Carbon
import AppKit

final class Shortcuts {
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var localMonitor: Any?
    var action: ((UInt32) -> Void)?
    @discardableResult func register() -> Bool {
        // App-targeted accessibility/automation key events need not pass through
        // Carbon's system hot-key dispatcher. Handle that local path as well.
        // Carbon consumes registered hardware shortcuts before local dispatch.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
            guard flags == [.control, .option, .command], !event.isARepeat else { return event }
            if event.keyCode == UInt16(kVK_ANSI_S) { self?.action?(1); return nil }
            if event.keyCode == UInt16(kVK_ANSI_M) { self?.action?(2); return nil }
            return event
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if result == noErr { Unmanaged<Shortcuts>.fromOpaque(context).takeUnretainedValue().action?(id.id) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        var success = true
        for (id, key) in [(UInt32(1), UInt32(kVK_ANSI_S)), (UInt32(2), UInt32(kVK_ANSI_M))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x534F4B4B, id: id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeys.append(ref) } else { success = false }
        }
        return success
    }
    deinit {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let handler { RemoveEventHandler(handler) }
    }
}
