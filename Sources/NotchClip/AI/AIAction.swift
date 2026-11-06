import Foundation

/// Something the AI can do with a clip.
enum AIAction: Hashable {
    case fixGrammar
    case formal
    case shorter
    case friendlier
    case summarize
    case explain
    case translate(String)
    case ask(String)

    /// The one-tap actions shown in the AI panel.
    static let quick: [AIAction] = [.fixGrammar, .formal, .shorter, .friendlier, .summarize, .explain]

    var title: String {
        switch self {
        case .fixGrammar: return "Fix grammar"
        case .formal: return "More formal"
        case .shorter: return "Shorter"
        case .friendlier: return "Friendlier"
        case .summarize: return "Summarise"
        case .explain: return "Explain"
        case .translate(let language): return "Translate to \(language)"
        case .ask(let question): return question
        }
    }

    var symbol: String {
        switch self {
        case .fixGrammar: return "checkmark.seal"
        case .formal: return "briefcase"
        case .shorter: return "scissors"
        case .friendlier: return "face.smiling"
        case .summarize: return "text.badge.minus"
        case .explain: return "lightbulb"
        case .translate: return "globe"
        case .ask: return "bubble.left"
        }
    }

    /// Rewrites give back text meant to be pasted; answers are for reading.
    var producesPasteableText: Bool {
        switch self {
        case .explain, .ask: return false
        default: return true
        }
    }

    static let rewriteRules = """
    You edit text the user copied to their clipboard. Reply with only the finished text: \
    no introduction, no quotes around it, no notes. Keep the original language unless asked \
    to translate, keep names, links, numbers and emojis, and keep line breaks where they help.
    """

    var instructions: String {
        switch self {
        case .fixGrammar:
            return Self.rewriteRules + " Fix spelling, grammar and punctuation only. Keep the wording and tone."
        case .formal:
            return Self.rewriteRules + " Rewrite it in a clear, polite, professional tone."
        case .shorter:
            return Self.rewriteRules + " Make it about half as long while keeping every important point."
        case .friendlier:
            return Self.rewriteRules + " Rewrite it in a warm, friendly, natural tone."
        case .summarize:
            return Self.rewriteRules + " Summarise it in 3–5 short bullet points starting with \"• \"."
        case .translate(let language):
            return Self.rewriteRules + " Translate it into \(language)."
        case .explain:
            return "Explain what the user copied in plain, simple English in under 120 words. If it is code or an error, say what it does or what went wrong and how to fix it."
        case .ask:
            return "Answer the user's question about what they copied. Be concise and practical."
        }
    }

    /// The user message: the clip, with the question first for "ask".
    func input(for clipText: String) -> String {
        if case .ask(let question) = self {
            return "Question: \(question)\n\nWhat I copied:\n\(clipText)"
        }
        return clipText
    }
}
