import AppKit
import NotchClipCore
import Security

/// Runs AI actions on clips with the provider chosen in Settings and streams the answer into the panel.
@MainActor
final class AIService {
    static let maxImagePixels = 1600

    private let settings: SettingsStore
    private let model: NotchModel
    private let store: ClipStore
    private var task: Task<Void, Never>?
    private var cachedModels: [AIProviderKind: String] = [:]

    init(settings: SettingsStore, model: NotchModel, store: ClipStore) {
        self.settings = settings
        self.model = model
        self.store = store
    }

    var providerName: String {
        switch settings.value.aiProvider {
        case .apple: return "Apple Intelligence · on this Mac"
        case .chatGPT: return "Using ChatGPT plan"
        case .openAIKey: return "OpenAI API key"
        }
    }

    func run(_ action: AIAction, on item: ClipItem) {
        cancel()
        model.aiProviderName = providerName
        model.aiRun = AIRun(item: item, action: action, status: .thinking)
        let runID = model.aiRun?.id
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let provider = try await self.provider()
                let request = try self.request(for: action, item: item, imagesAllowed: provider.supportsImages)
                var latest = ""
                for try await text in provider.stream(request) {
                    guard !Task.isCancelled, self.model.aiRun?.id == runID else { return }
                    latest = text
                    self.model.aiRun?.status = .writing(Self.clean(text))
                }
                let final = Self.clean(latest)
                guard !final.isEmpty else { throw AIError.emptyAnswer }
                self.model.aiRun?.status = .done(final)
            } catch is CancellationError {
                return
            } catch {
                guard self.model.aiRun?.id == runID else { return }
                self.model.aiRun?.status = .failed(Self.message(for: error))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: Building the request

    private func request(for action: AIAction, item: ClipItem, imagesAllowed: Bool) throws -> AIRequest {
        var image: Data?
        if item.kind == .image, imagesAllowed, let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) {
            image = ClipStore.thumbnail(of: data, maxPixels: Self.maxImagePixels) ?? data
        }
        let text = item.workingText ?? (image != nil ? "(See the attached screenshot.)" : nil)
        guard let text else { throw AIError.nothingToWorkOn }
        return AIRequest(instructions: action.instructions, text: action.input(for: text), imagePNG: image)
    }

    // MARK: Providers

    private func provider() async throws -> AIProvider {
        switch settings.value.aiProvider {
        case .apple:
            return AppleProvider()
        case .chatGPT:
            let token = try await ChatGPTAuth.shared.accessToken()
            let slug = try await modelSlug(for: .chatGPT, token: token, planUsage: true)
            return ResponsesClient(name: "ChatGPT", model: slug) { try await ChatGPTAuth.shared.accessToken() }
        case .openAIKey:
            guard let key = Keychain.apiKey, !key.isEmpty else { throw AIError.missingKey }
            let slug = try await modelSlug(for: .openAIKey, token: key, planUsage: false)
            return ResponsesClient(name: "OpenAI", model: slug) { key }
        }
    }

    /// The model picked in Settings, or the first one the account offers.
    private func modelSlug(for kind: AIProviderKind, token: String, planUsage: Bool) async throws -> String {
        if let chosen = settings.value.aiModel, !chosen.isEmpty { return chosen }
        if let cached = cachedModels[kind] { return cached }
        guard let first = try await ResponsesClient.listModels(token: token, planUsage: planUsage).first else {
            throw AIError.server("No AI models are available for this account.")
        }
        cachedModels[kind] = first.slug
        return first.slug
    }

    func forgetModelCache() {
        cachedModels = [:]
    }

    // MARK: Helpers

    /// Strips wrapping quotes or code fences some models add around rewrites.
    static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```"), result.hasSuffix("```"), result.count > 6 {
            result = String(result.dropFirst(3).dropLast(3))
            if let newline = result.firstIndex(of: "\n"), !result[..<newline].contains(" ") {
                result = String(result[result.index(after: newline)...])
            }
        }
        if result.count > 1, result.hasPrefix("\""), result.hasSuffix("\""), result.dropFirst().dropLast().contains("\"") == false {
            result = String(result.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func message(for error: Error) -> String {
        if let aiError = error as? AIError { return aiError.localizedDescription }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "You're offline. Connect to the internet, or use Apple Intelligence." : "Network problem: \(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }
}

/// The optional OpenAI API key, kept in the login Keychain.
enum Keychain {
    private static let service = "com.minutechbuilds.notchclip"
    private static let account = "openai-api-key"

    static var apiKey: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String?) -> Bool {
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        var item = base
        item[kSecValueData] = Data(key.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
