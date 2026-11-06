import Carbon.HIToolbox

/// A system-wide keyboard shortcut (Carbon hot key). Works without any permission.
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// Default shortcut: Control + Shift + C.
    static let defaultKeyCode = UInt32(kVK_ANSI_C)
    static let defaultModifiers = UInt32(controlKey | shiftKey)

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, action: @escaping () -> Void) {
        self.id = id
        guard Self.installHandler() else { return nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E43_4C50), id: id) // "NCLP"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.actions[id] = action
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }

    private static func installHandler() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            if result == noErr, let action = HotKey.actions[hotKeyID.id] {
                DispatchQueue.main.async(execute: action)
            }
            return noErr
        }, 1, &spec, nil, &handler)
        return status == noErr
    }
}
