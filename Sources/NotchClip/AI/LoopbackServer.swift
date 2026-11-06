import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that catches the OAuth redirect from the browser.
final class LoopbackServer: @unchecked Sendable {
    static let path = "/auth/callback"
    static let preferredPort: UInt16 = 1455

    private var listener: NWListener!
    private let queue = DispatchQueue(label: "NotchClip.LoopbackServer")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var pending: Result<[String: String], Error>?
    private var finished = false

    private(set) var port: UInt16 = 0

    /// Starts listening on 127.0.0.1; tries the preferred port first (OpenAI expects it for first-time registration),
    /// then any free port. Returns only once the listener is ready, so `port` is the real bound port.
    init() throws {
        for candidate in [Self.preferredPort, 0] {
            guard let nwPort = NWEndpoint.Port(rawValue: candidate) else { continue }
            if let (listener, bound) = startListener(on: nwPort) {
                self.listener = listener
                self.port = bound
                return
            }
        }
        throw AIError.server("Couldn't start the sign-in listener.")
    }

    var redirectURI: String { "http://127.0.0.1:\(port)\(Self.path)" }

    private func startListener(on port: NWEndpoint.Port) -> (NWListener, UInt16)? {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        guard let listener = try? NWListener(using: parameters) else { return nil }
        let ready = DispatchSemaphore(value: 0)
        let outcome = Outcome()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: outcome.ok = true; ready.signal()
            case .failed, .cancelled: ready.signal()
            default: break
            }
        }
        // The handler must be set before start(), or the listener never accepts connections.
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success, outcome.ok,
              let bound = listener.port?.rawValue, bound != 0 else {
            listener.cancel()
            return nil
        }
        listener.stateUpdateHandler = nil
        return (listener, bound)
    }

    private final class Outcome: @unchecked Sendable { var ok = false }

    /// Waits for the browser to hit the callback and returns its query parameters.
    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let pending = self.pending {
                    self.pending = nil
                    continuation.resume(with: pending)
                    return
                }
                self.continuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(AIError.server("Sign-in timed out. Please try again.")))
                }
            }
        }
    }

    func stop() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let components = URLComponents(string: "http://127.0.0.1\(target)")
            guard components?.path == Self.path else {
                self.respond(connection, status: "404 Not Found", body: "Not found")
                return
            }
            var params: [String: String] = [:]
            components?.queryItems?.forEach { params[$0.name] = $0.value ?? "" }
            let ok = params["error"] == nil
            self.respond(connection, status: "200 OK", body: Self.page(success: ok))
            self.finish(.success(params))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard !finished else { return }
        finished = true
        queue.asyncAfter(deadline: .now() + 1) { self.listener.cancel() }
        guard let continuation else { pending = result; return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func page(success: Bool) -> String {
        let title = success ? "You're connected" : "Sign-in was cancelled"
        let message = success ? "You can close this tab and go back to Pocket." : "You can close this tab and try again from Pocket."
        return """
        <!doctype html><meta charset="utf-8"><title>Pocket</title>
        <body style="font-family:-apple-system,sans-serif;background:#0A0A0A;color:#fff;display:grid;place-items:center;height:100vh;margin:0">
        <div style="text-align:center"><div style="font-size:44px">\(success ? "✅" : "✋")</div>
        <h2 style="margin:12px 0 6px">\(title)</h2><p style="color:#999">\(message)</p></div></body>
        """
    }
}
