import Foundation

/// A keyboard shortcut as Carbon key code + Carbon modifier mask.
public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Carbon modifier bits (from HIToolbox Events.h).
    public static let commandBit: UInt32 = 1 << 8
    public static let shiftBit: UInt32 = 1 << 9
    public static let optionBit: UInt32 = 1 << 11
    public static let controlBit: UInt32 = 1 << 12

    /// Ctrl + Shift + C opens the clipboard.
    public static let openDefault = Shortcut(keyCode: 8, modifiers: controlBit | shiftBit)
    /// Ctrl + Shift + V pastes the next clip in the paste stack.
    public static let stackDefault = Shortcut(keyCode: 9, modifiers: controlBit | shiftBit)
}

/// Which AI does the work for AI actions.
public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case apple
    case chatGPT
    case openAIKey

    public var title: String {
        switch self {
        case .apple: return "Apple Intelligence (on this Mac)"
        case .chatGPT: return "ChatGPT (your plan)"
        case .openAIKey: return "OpenAI API key"
        }
    }
}

/// An app whose copies are never saved.
public struct IgnoredApp: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// Everything the user can change in Settings. Stored as JSON in UserDefaults.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let historyChoices = [25, 50, 100, 200, 500]
    public static let autoDeleteChoices = [0, 1, 7, 30, 90]

    public var historyLimit = 50
    /// Delete unpinned clips after this many days; 0 keeps them until the history is full.
    public var autoDeleteDays = 0
    public var keepFormatting = true
    public var openShortcut = Shortcut.openDefault
    public var stackShortcut = Shortcut.stackDefault
    public var ignoredApps: [IgnoredApp] = AppSettings.defaultIgnoredApps
    public var aiProvider = AIProviderKind.apple
    /// Model slug for ChatGPT / API key requests; nil picks the first listed model.
    public var aiModel: String?
    public var translateLanguages = ["English", "Arabic", "Sinhala", "Tamil", "Hindi", "French", "Spanish"]
    public var hasSeenChatGPTWelcome = false

    public init() {}

    public static let defaultIgnoredApps = [
        IgnoredApp(name: "Keychain Access", bundleID: "com.apple.keychainaccess"),
        IgnoredApp(name: "Passwords", bundleID: "com.apple.Passwords"),
        IgnoredApp(name: "1Password", bundleID: "com.1password.1password"),
        IgnoredApp(name: "Bitwarden", bundleID: "com.bitwarden.desktop"),
    ]

    /// Decodes saved settings; any field missing from an older version keeps its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = AppSettings()
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? base.historyLimit
        autoDeleteDays = try c.decodeIfPresent(Int.self, forKey: .autoDeleteDays) ?? base.autoDeleteDays
        keepFormatting = try c.decodeIfPresent(Bool.self, forKey: .keepFormatting) ?? base.keepFormatting
        openShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .openShortcut) ?? base.openShortcut
        stackShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .stackShortcut) ?? base.stackShortcut
        ignoredApps = try c.decodeIfPresent([IgnoredApp].self, forKey: .ignoredApps) ?? base.ignoredApps
        aiProvider = try c.decodeIfPresent(AIProviderKind.self, forKey: .aiProvider) ?? base.aiProvider
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel)
        translateLanguages = try c.decodeIfPresent([String].self, forKey: .translateLanguages) ?? base.translateLanguages
        hasSeenChatGPTWelcome = try c.decodeIfPresent(Bool.self, forKey: .hasSeenChatGPTWelcome) ?? false
    }

    public func ignores(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredApps.contains { $0.bundleID == bundleID }
    }

    public static func load(from defaults: UserDefaults, key: String = "settings") -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults, key: String = "settings") {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
    }
}
