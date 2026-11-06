import AppKit
import Carbon.HIToolbox
import NotchClipCore

/// The app's settings, saved to UserDefaults on every change.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet {
            guard value != oldValue else { return }
            value.save(to: defaults)
            onChange?(oldValue, value)
        }
    }

    var onChange: ((AppSettings, AppSettings) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.value = AppSettings.load(from: defaults)
    }
}

extension Shortcut {
    /// "⌃⇧C" style label.
    var label: String {
        var text = ""
        if modifiers & Shortcut.controlBit != 0 { text += "⌃" }
        if modifiers & Shortcut.optionBit != 0 { text += "⌥" }
        if modifiers & Shortcut.shiftBit != 0 { text += "⇧" }
        if modifiers & Shortcut.commandBit != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// Builds a shortcut from a key press; needs at least one of ⌘ ⌃ ⌥.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= Shortcut.commandBit }
        if flags.contains(.control) { modifiers |= Shortcut.controlBit }
        if flags.contains(.option) { modifiers |= Shortcut.optionBit }
        if flags.contains(.shift) { modifiers |= Shortcut.shiftBit }
        guard modifiers & (Shortcut.commandBit | Shortcut.controlBit | Shortcut.optionBit) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        if let name = special[Int(code)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let layout = unsafeBitCast(layoutPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layout) else { return "?" }
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
