import Foundation

/// A model the user can pick.
struct AIModel: Identifiable, Hashable, Sendable {
    let slug: String
    let displayName: String
    var id: String { slug }
}

/// Talks to OpenAI's Responses API, either with a "Sign in with ChatGPT" token (plan usage)
/// or with the user's own API key. Streams text as it arrives.
struct ResponsesClient: AIProvider {
    static let base = URL(string: "https://api.openai.com/v1")!

    let name: String
    let supportsImages = true
    let model: String
    /// Returns a fresh bearer token (access token or API key).
    let token: @Sendable () async throws -> String

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: AIRequest, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        var urlRequest = URLRequest(url: Self.base.appendingPathComponent("responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes.prefix(64 * 1024) { data.append(byte) }
            throw Self.error(status: status, body: data)
        }

        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "response.output_text.delta":
                text += event["delta"] as? String ?? ""
                continuation.yield(text)
            case "response.completed":
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.emptyAnswer }
                return
            case "response.failed", "error":
                let error = (event["response"] as? [String: Any])?["error"] as? [String: Any] ?? event
                throw Self.error(code: error["code"] as? String, message: error["message"] as? String)
            case "response.incomplete":
                throw AIError.server("The answer was cut off. Try a shorter clip.")
            default:
                continue
            }
        }
        throw AIError.server("The connection ended before the answer finished. Try again.")
    }

    private func body(for request: AIRequest) -> [String: Any] {
        var content: [[String: Any]] = [["type": "input_text", "text": request.text]]
        if let png = request.imagePNG {
            content.append(["type": "input_image", "image_url": "data:image/png;base64,\(png.base64EncodedString())"])
        }
        return [
            "model": model,
            "instructions": request.instructions,
            "input": [["role": "user", "content": content]],
            "store": false,
            "stream": true,
        ]
    }

    // MARK: Errors

    static func error(status: Int, body: Data) -> AIError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        if let code = error?["code"] as? String {
            return Self.error(code: code, message: error?["message"] as? String)
        }
        switch status {
        case 401: return .notSignedIn
        case 429: return .usageLimit
        default:
            let detail = (json?["detail"] as? String) ?? (error?["message"] as? String) ?? "HTTP \(status)"
            return .server("OpenAI couldn't answer: \(detail)")
        }
    }

    static func error(code: String?, message: String?) -> AIError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded", "rate_limit_exceeded", "insufficient_quota":
            return .usageLimit
        case "subscription_sharing_user_not_eligible":
            return .server("ChatGPT plan use isn't available for this account or workspace.")
        case "subscription_sharing_invalid_user", "invalid_api_key":
            return .notSignedIn
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return .server("ChatGPT is busy right now. Try again in a minute.")
        default:
            return .server(message ?? "OpenAI couldn't answer (\(code ?? "unknown error")).")
        }
    }

    // MARK: Models

    /// Models the signed-in ChatGPT account (or API key) can use, in the server's order.
    static func listModels(token: String, planUsage: Bool) async throws -> [AIModel] {
        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw error(status: status, body: data) }
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if planUsage, let models = json["models"] as? [[String: Any]] {
            return models.compactMap { model in
                guard (model["visibility"] as? String) == "list", let slug = model["slug"] as? String else { return nil }
                return AIModel(slug: slug, displayName: model["display_name"] as? String ?? slug)
            }
        }
        let ids = ((json["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        return ids.filter { $0.hasPrefix("gpt-") && !$0.contains("audio") && !$0.contains("realtime") && !$0.contains("image") }
            .sorted(by: >)
            .map { AIModel(slug: $0, displayName: $0) }
    }
}
