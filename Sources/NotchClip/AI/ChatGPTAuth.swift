import CryptoKit
import Foundation

/// "Sign in with ChatGPT" with ChatGPT plan usage, following OpenAI's open-source client guide:
/// dynamic client registration, PKCE over a 127.0.0.1 loopback redirect, ID-token checks,
/// token refresh and revocation. Credentials stay in an owner-only file on this Mac.
actor ChatGPTAuth {
    static let shared = ChatGPTAuth()

    static let appName = "NotchClip"
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let resource = "https://api.openai.com/v1"
    static let planScope = "chatgpt.tokens.use.direct"
    static let scopes = "openid profile email offline_access resource.invoke \(planScope)"
    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!

    enum State: Equatable, Sendable {
        case signedOut
        case connected(email: String?, planUsage: Bool)
    }

    /// One ChatGPT account registration. Tokens are cleared on sign-out; the client ID is kept.
    struct Registration: Codable {
        var clientID: String
        var email: String?
        var subject: String?
        var idToken: String?
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Date?
        var scopes: [String] = []
    }

    private let directory: URL
    private var registration: Registration?
    private var refreshTask: Task<String, Error>?

    init(directory: URL = ClipStoreDirectory.chatGPT) {
        self.directory = directory
        registration = Self.read(Registration.self, from: directory.appendingPathComponent("auth.json"))
    }

    var state: State {
        guard let registration, registration.refreshToken != nil else { return .signedOut }
        return .connected(email: registration.email, planUsage: registration.scopes.contains(Self.planScope))
    }

    // MARK: Sign in

    /// Opens the browser for consent and waits for the redirect. `open` must show the URL to the user.
    func signIn(open: @Sendable (URL) async -> Void) async throws -> State {
        let server = try LoopbackServer()
        defer { server.stop() }
        let state = Self.randomToken()
        let nonce = Self.randomToken()
        let verifier = Self.randomToken()
        let existing = registration

        await open(authorizationURL(redirectURI: server.redirectURI, state: state, nonce: nonce, verifier: verifier, existing: existing))
        let callback = try await server.waitForCallback(timeout: 300)

        guard callback["state"] == state else { throw AIError.server("Sign-in didn't match. Please try again.") }
        if let error = callback["error"] {
            throw error == "access_denied" ? AIError.planNotEnabled : AIError.server("ChatGPT sign-in failed (\(error)).")
        }
        guard let code = callback["code"] else { throw AIError.server("ChatGPT didn't send a sign-in code.") }

        // New registrations get their issued client ID in the callback; save it before the exchange.
        let clientID: String
        if let existing {
            if let returned = callback["client_id"], returned != existing.clientID {
                throw AIError.server("ChatGPT returned a different app registration. Please try again.")
            }
            clientID = existing.clientID
        } else {
            guard let issued = callback["client_id"], issued != "dynamic_agent_client" else {
                throw AIError.server("ChatGPT didn't finish registering NotchClip. Please try again.")
            }
            clientID = issued
            registration = Registration(clientID: issued)
            persist()
        }

        let tokens = try await tokenRequest([
            "grant_type": "authorization_code", "client_id": clientID, "code": code,
            "code_verifier": verifier, "redirect_uri": server.redirectURI, "resource": Self.resource,
        ])
        guard let idToken = tokens["id_token"] as? String else {
            throw AIError.server("ChatGPT didn't return a verifiable identity. Please try signing in again.")
        }
        let claims = try await IDToken.verify(idToken, clientID: clientID, nonce: nonce)
        if let subject = existing?.subject, subject != claims.subject {
            throw AIError.server("That's a different ChatGPT account. Sign out first to switch accounts.")
        }
        registration = Registration(clientID: clientID, email: claims.email, subject: claims.subject, idToken: idToken)
        apply(tokens)
        return self.state
    }

    private func authorizationURL(redirectURI: String, state: String, nonce: String, verifier: String,
                                  existing: Registration?) -> URL {
        let challenge = IDToken.base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: existing?.clientID ?? "dynamic_agent_client"),
            .init(name: "ext_agent_host_id", value: hostID()),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "resource", value: Self.resource),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]
        if let existing {
            if let idToken = existing.idToken { items.append(.init(name: "id_token_hint", value: idToken)) }
            if let email = existing.email { items.append(.init(name: "login_hint", value: email)) }
            // Ask again for plan usage if it was declined last time.
            if !existing.scopes.isEmpty, !existing.scopes.contains(Self.planScope) {
                items.append(.init(name: "prompt", value: "consent"))
            }
        } else {
            items.append(.init(name: "agent_name_hint", value: Self.appName))
        }
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryValue))
        }
        return components.url!
    }

    // MARK: Tokens

    /// A valid access token, refreshed when it's about to expire. Throws if plan usage isn't granted.
    func accessToken() async throws -> String {
        guard let registration, registration.refreshToken != nil else { throw AIError.notSignedIn }
        guard registration.scopes.contains(Self.planScope) else { throw AIError.planNotEnabled }
        if let token = registration.accessToken, let expiry = registration.expiresAt, expiry > Date().addingTimeInterval(90) {
            return token
        }
        // Serialize refreshes: refresh tokens rotate, so two at once would break the session.
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.refresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refresh() async throws -> String {
        guard let current = registration, let refreshToken = current.refreshToken else { throw AIError.notSignedIn }
        do {
            let tokens = try await tokenRequest([
                "grant_type": "refresh_token", "client_id": current.clientID,
                "refresh_token": refreshToken, "resource": Self.resource,
            ])
            apply(tokens)
            guard let token = registration?.accessToken else { throw AIError.notSignedIn }
            return token
        } catch let OAuthError.rejected(code) where Self.terminalRefreshErrors.contains(code) {
            clearTokens()
            throw AIError.notSignedIn
        }
    }

    private static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused",
    ]

    private func apply(_ tokens: [String: Any]) {
        guard var updated = registration else { return }
        if let access = tokens["access_token"] as? String { updated.accessToken = access }
        if let refresh = tokens["refresh_token"] as? String { updated.refreshToken = refresh }
        if let idToken = tokens["id_token"] as? String { updated.idToken = idToken }
        if let expiresIn = tokens["expires_in"] as? Double { updated.expiresAt = Date().addingTimeInterval(expiresIn) }
        if let scope = tokens["scope"] as? String { updated.scopes = scope.split(separator: " ").map(String.init).sorted() }
        registration = updated
        persist()
    }

    // MARK: Sign out

    /// Revokes the session with OpenAI (best effort), then forgets the tokens. Keeps the registration.
    func signOut() async -> Bool {
        var revoked = false
        if let current = registration, let refreshToken = current.refreshToken,
           let endpoint = (try? await IDToken.discovery())?["revocation_endpoint"] as? String,
           let url = URL(string: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": refreshToken, "token_type_hint": "refresh_token", "client_id": current.clientID])
            revoked = ((try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse)?.statusCode == 200
        }
        clearTokens()
        return revoked
    }

    private func clearTokens() {
        guard var current = registration else { return }
        current.accessToken = nil
        current.refreshToken = nil
        current.expiresAt = nil
        registration = current
        persist()
    }

    // MARK: Plumbing

    enum OAuthError: Error { case rejected(String) }

    private func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OAuthError.rejected(json["error"] as? String ?? "http_\((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return json
    }

    private func hostID() -> String {
        let url = directory.appendingPathComponent("host.json")
        if let saved = Self.read([String: String].self, from: url)?["ext_agent_host_id"] { return saved }
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        Self.write(["ext_agent_host_id": id], to: url)
        return id
    }

    private func persist() {
        Self.write(registration, to: directory.appendingPathComponent("auth.json"))
    }

    private static func form(_ fields: [String: String]) -> Data {
        Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValue) ?? "")" }
            .joined(separator: "&").utf8)
    }

    private static func randomToken() -> String {
        IDToken.base64URLEncode(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    /// Writes atomically and makes the file readable by this user only (0600).
    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Where NotchClip keeps ChatGPT sign-in files.
enum ClipStoreDirectory {
    static var chatGPT: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchClip/chatgpt", isDirectory: true)
    }
}

extension CharacterSet {
    /// Characters allowed unescaped in a query value (RFC 3986 unreserved).
    static let urlQueryValue = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
