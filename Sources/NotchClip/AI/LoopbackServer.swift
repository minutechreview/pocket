import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that catches the OAuth redirect from the browser.
final class LoopbackServer: @unchecked Sendable {
    static let path = "/auth/callback"
    static let preferredPort: UInt16 = 1455

    private let listener: NWListener
    private let queue = DispatchQueue(label: "NotchClip.LoopbackServer")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var finished = false

    let port: UInt16

    /// Starts listening; tries the preferred port first, then any free port.
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener: NWListener
        if let preferred = NWEndpoint.Port(rawValue: Self.preferredPort),
           let fixed = try? Self.makeListener(port: preferred) {
            listener = fixed
        } else {
            listener = try Self.makeListener(port: .any)
        }
        self.listener = listener
        listener.start(queue: queue)
        // Wait briefly for the system to assign the port.
        let deadline = Date().addingTimeInterval(2)
        while listener.port == nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard let port = listener.port?.rawValue else { throw AIError.server("Couldn't start the sign-in listener.") }
        self.port = port
    }

    var redirectURI: String { "http://127.0.0.1:\(port)\(Self.path)" }

    private static func makeListener(port: NWEndpoint.Port) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        return try NWListener(using: parameters, on: port)
    }

    /// Waits for the browser to hit the callback and returns its query parameters.
    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
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
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        continuation.resume(with: result)
        queue.asyncAfter(deadline: .now() + 1) { self.listener.cancel() }
    }

    private static func page(success: Bool) -> String {
        let title = success ? "You're connected" : "Sign-in was cancelled"
        let message = success ? "You can close this tab and go back to NotchClip." : "You can close this tab and try again from NotchClip."
        return """
        <!doctype html><meta charset="utf-8"><title>NotchClip</title>
        <body style="font-family:-apple-system,sans-serif;background:#0A0A0A;color:#fff;display:grid;place-items:center;height:100vh;margin:0">
        <div style="text-align:center"><div style="font-size:44px">\(success ? "✅" : "✋")</div>
        <h2 style="margin:12px 0 6px">\(title)</h2><p style="color:#999">\(message)</p></div></body>
        """
    }
}
