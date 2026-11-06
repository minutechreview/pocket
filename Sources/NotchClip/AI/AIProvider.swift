import Foundation
import FoundationModels

/// One AI request: what to do, the text, and optionally the picture.
struct AIRequest: Sendable {
    let instructions: String
    let text: String
    let imagePNG: Data?
}

enum AIError: LocalizedError, Equatable {
    case unavailable(String)
    case notSignedIn
    case planNotEnabled
    case usageLimit
    case missingKey
    case nothingToWorkOn
    case emptyAnswer
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .notSignedIn: return "Sign in with ChatGPT in Settings → AI."
        case .planNotEnabled: return "ChatGPT plan use isn't turned on. Reconnect in Settings → AI."
        case .usageLimit: return "You've reached your ChatGPT usage limit for now."
        case .missingKey: return "Add your OpenAI API key in Settings → AI."
        case .nothingToWorkOn: return "This clip has no text to work with."
        case .emptyAnswer: return "The AI sent back an empty answer. Try again."
        case .server(let message): return message
        }
    }
}

/// Something that can answer an `AIRequest`. Streams the whole answer so far, growing each time.
protocol AIProvider: Sendable {
    var name: String { get }
    var supportsImages: Bool { get }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
}

/// Apple Intelligence's on-device model: free, private, works offline. Text only.
struct AppleProvider: AIProvider {
    /// The on-device model has a small context window, so long clips are trimmed.
    static let maxInputCharacters = 9_000

    let name = "Apple Intelligence"
    let supportsImages = false

    /// nil when ready; otherwise a plain explanation of why it can't run.
    static var unavailableReason: String? {
        guard #available(macOS 26, *) else {
            return "Apple Intelligence needs macOS 26 or newer. Choose ChatGPT in Settings → AI."
        }
        return currentReason()
    }

    @available(macOS 26, *)
    private static func currentReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use on-device AI."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable(.deviceNotEligible):
            return "This Mac can't run Apple Intelligence. Choose ChatGPT in Settings → AI."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let reason = Self.unavailableReason { throw AIError.unavailable(reason) }
                    if #available(macOS 26, *) {
                        try await Self.respond(request) { continuation.yield($0) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @available(macOS 26, *)
    private static func respond(_ request: AIRequest, yield: (String) -> Void) async throws {
        let session = LanguageModelSession(instructions: request.instructions)
        let prompt = String(request.text.prefix(maxInputCharacters))
        for try await snapshot in session.streamResponse(to: prompt) {
            yield(snapshot.content)
        }
    }
}
