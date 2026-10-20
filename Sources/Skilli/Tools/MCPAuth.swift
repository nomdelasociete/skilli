import AppKit
import SkilliCore

/// Signing in to MCP servers: a token the user pastes, or OAuth as the MCP
/// spec says (`MCPOAuth`): the browser opens on the server's sign-in page
/// and comes back to skil.li on 127.0.0.1. Secrets stay in skil.li's
/// Keychain; each agent run gets a fresh `Authorization` header in its own
/// private MCP config file.
@MainActor
final class MCPAuth {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let keychainPrefix: String
    /// Where sign-in pages open; the self-test follows them itself.
    var openBrowser: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// How long the browser has to come back.
    var signInTimeout: Duration = .seconds(300)
    private let http = URLSession(configuration: .ephemeral)

    init(keychainPrefix: String) {
        self.keychainPrefix = keychainPrefix
    }

    // MARK: - Pasted tokens

    func token(for server: String) -> String? {
        Keychain.read(account: keychainPrefix + "mcp-token-" + server)
    }

    /// Empty removes it.
    func setToken(_ token: String, for server: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            Keychain.delete(account: keychainPrefix + "mcp-token-" + server)
        } else {
            try? Keychain.save(token, account: keychainPrefix + "mcp-token-" + server)
        }
    }

    // MARK: - OAuth sessions

    func session(for server: String) -> MCPOAuth.Session? {
        Keychain.read(account: keychainPrefix + "mcp-oauth-" + server)
            .flatMap { try? JSONDecoder().decode(MCPOAuth.Session.self, from: Data($0.utf8)) }
    }

    private func save(_ session: MCPOAuth.Session, for server: String) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? Keychain.save(String(decoding: data, as: UTF8.self), account: keychainPrefix + "mcp-oauth-" + server)
    }

    func signOut(_ server: String) {
        Keychain.delete(account: keychainPrefix + "mcp-oauth-" + server)
    }

    /// The server is gone: nothing of it stays.
    func forget(_ server: String) {
        signOut(server)
        setToken("", for: server)
    }

    /// A server's token and sign-in as kept, in memory while ⌘Z can put
    /// them back (`ToolSettings.restore`); never logged.
    struct Kept {
        fileprivate let token: String?
        fileprivate let session: String?
        var isEmpty: Bool { token == nil && session == nil }
    }

    func kept(for server: String) -> Kept {
        Kept(token: token(for: server), session: Keychain.read(account: keychainPrefix + "mcp-oauth-" + server))
    }

    func putBack(_ kept: Kept, for server: String) {
        if let token = kept.token { setToken(token, for: server) }
        if let session = kept.session { try? Keychain.save(session, account: keychainPrefix + "mcp-oauth-" + server) }
    }

    /// What Settings says under the server.
    func status(of server: MCPServerConfig) -> String? {
        switch server.auth {
        case .token: token(for: server.name) == nil ? "No token yet" : "Token in the Keychain"
        case .oauth: session(for: server.name) == nil ? "Not signed in" : "Signed in"
        case nil: nil
        }
    }

    /// The headers an agent run sends to this server; signs in again with
    /// the refresh token when the access token is about to expire.
    func headers(for server: MCPServerConfig) async throws -> [String: String] {
        switch server.auth {
        case nil:
            return [:]
        case .token:
            guard let token = token(for: server.name) else { throw Failure(message: "“\(server.name)” has no token: Settings → Tools → Edit.") }
            let name = server.header.flatMap { $0.isEmpty ? nil : $0 } ?? "Authorization"
            let bare = name.lowercased() == "authorization" && !["bearer ", "basic "].contains(where: token.lowercased().hasPrefix)
            return [name: bare ? "Bearer \(token)" : token]
        case .oauth:
            guard var session = session(for: server.name) else {
                throw Failure(message: "Sign in to “\(server.name)” first: Settings → Tools → Sign In.")
            }
            // Signed in for another address: never sent anywhere else.
            guard let host = server.url.flatMap(URL.init(string:))?.host, host == URL(string: session.resource)?.host else {
                signOut(server.name)
                throw Failure(message: "“\(server.name)” changed address: sign in again in Settings → Tools.")
            }
            if session.needsRefresh() {
                session = try await refresh(session, server: server.name)
            }
            return ["Authorization": "Bearer \(session.accessToken)"]
        }
    }

    private func refresh(_ session: MCPOAuth.Session, server: String) async throws -> MCPOAuth.Session {
        guard let refreshToken = session.refreshToken else {
            signOut(server)
            throw Failure(message: "“\(server)” signed you out: sign in again in Settings → Tools.")
        }
        var fields = [("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", session.clientID), ("resource", session.resource)]
        if let secret = session.clientSecret { fields.append(("client_secret", secret)) }
        guard let tokens = try? await post(form: fields, to: session.tokenEndpoint).flatMap({ MCPOAuth.tokens($0) }) else {
            signOut(server)
            throw Failure(message: "“\(server)” did not renew the sign-in: sign in again in Settings → Tools.")
        }
        var renewed = session
        renewed.accessToken = tokens.access
        renewed.refreshToken = tokens.refresh ?? refreshToken
        renewed.expiresAt = tokens.expiresAt
        save(renewed, for: server)
        Log.trace("MCP sign-in renewed for \(server)")
        return renewed
    }

    // MARK: - Signing in

    /// The whole OAuth sign-in: discovery, registration, the browser, the
    /// tokens. Throws what went wrong, in words.
    func signIn(_ server: MCPServerConfig) async throws {
        guard let address = server.url, MCPOAuth.isAllowed(address), let url = URL(string: address) else {
            throw Failure(message: "Signing in needs an https:// address.")
        }
        // 1. The server says where its sign-in is.
        var probe = URLRequest(url: url)
        probe.httpMethod = "POST"
        probe.setValue("application/json", forHTTPHeaderField: "Content-Type")
        probe.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        probe.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"skil.li","version":"1"}}}"#.utf8)
        let (_, answer) = try await http.data(for: probe)
        let challenge = MCPOAuth.challenge((answer as? HTTPURLResponse)?.value(forHTTPHeaderField: "WWW-Authenticate") ?? "")
        guard let metadataURL = challenge.resourceMetadata.flatMap(URL.init(string:)) ?? MCPOAuth.resourceMetadataURL(for: url),
              let resource = try? JSONDecoder().decode(MCPOAuth.ResourceMetadata.self, from: try await get(metadataURL)) else {
            throw Failure(message: "“\(server.name)” does not say how to sign in (no OAuth metadata).")
        }
        let issuer = resource.authorizationServers?.first.flatMap(URL.init(string:)) ?? url
        guard MCPOAuth.isAllowed(metadataURL.absoluteString), MCPOAuth.isAllowed(issuer.absoluteString) else {
            throw Failure(message: "“\(server.name)” points its sign-in to a plain http address: refused.")
        }
        var metadata: MCPOAuth.ServerMetadata?
        for candidate in MCPOAuth.serverMetadataURLs(issuer: issuer) {
            if let data = try? await get(candidate), let found = try? JSONDecoder().decode(MCPOAuth.ServerMetadata.self, from: data) {
                metadata = found
                break
            }
        }
        guard let metadata else { throw Failure(message: "“\(server.name)”'s sign-in server does not describe itself.") }
        // The code and the tokens travel only over https (or on this Mac).
        guard [metadata.authorizationEndpoint, metadata.tokenEndpoint, metadata.registrationEndpoint ?? "https://x"].allSatisfy(MCPOAuth.isAllowed) else {
            throw Failure(message: "“\(server.name)”'s sign-in uses a plain http address: refused.")
        }
        if let methods = metadata.codeChallengeMethodsSupported, !methods.contains("S256") {
            throw Failure(message: "“\(server.name)”'s sign-in does not support PKCE (S256).")
        }

        // 2. Where the browser comes back.
        let box = CallbackBox()
        guard let loopback = LoopbackServer(handler: { request in
            guard request.target.hasPrefix("/callback") else { return LoopbackServer.Response(status: 404) }
            box.deliver(MCPOAuth.callback(request.target))
            return .html(Self.page)
        }), let port = await loopback.port() else { throw Failure(message: "skil.li could not listen for the sign-in's return.") }
        defer { loopback.stop() }
        let redirect = "http://127.0.0.1:\(port)/callback"

        // 3. skil.li registers as a client of this server.
        guard let registration = metadata.registrationEndpoint, let registrationURL = URL(string: registration) else {
            throw Failure(message: "“\(server.name)” does not let apps register (no dynamic client registration).")
        }
        var register = URLRequest(url: registrationURL)
        register.httpMethod = "POST"
        register.setValue("application/json", forHTTPHeaderField: "Content-Type")
        register.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "skil.li", "redirect_uris": [redirect], "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"], "token_endpoint_auth_method": "none"
        ])
        let (registered, _) = try await http.data(for: register)
        guard let client = try? JSONSerialization.jsonObject(with: registered) as? [String: Any], let clientID = client["client_id"] as? String else {
            throw Failure(message: "“\(server.name)” refused to register skil.li.")
        }

        // 4. The browser: the user signs in there, skil.li never sees it.
        let verifier = MCPOAuth.makeVerifier()
        let state = MCPOAuth.makeVerifier()
        let scope = challenge.scope ?? resource.scopesSupported?.joined(separator: " ")
        let resourceID = resource.resource ?? address
        guard let authorize = MCPOAuth.authorizationURL(endpoint: metadata.authorizationEndpoint, clientID: clientID, redirect: redirect,
                                                        challenge: MCPOAuth.challenge(for: verifier), state: state, scope: scope,
                                                        resource: resourceID) else {
            throw Failure(message: "“\(server.name)”'s sign-in address is not valid.")
        }
        Log.trace("MCP sign-in for \(server.name): browser opened")
        openBrowser(authorize)
        guard let back = await box.wait(timeout: signInTimeout) else { throw Failure(message: "The sign-in did not come back in time.") }
        if let error = back.error { throw Failure(message: "“\(server.name)” said: \(error)") }
        guard back.state == state, let code = back.code else { throw Failure(message: "The sign-in came back without its code.") }

        // 5. The code for tokens.
        var fields = [("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirect), ("client_id", clientID),
                      ("code_verifier", verifier), ("resource", resourceID)]
        let secret = client["client_secret"] as? String
        if let secret { fields.append(("client_secret", secret)) }
        guard let tokens = try await post(form: fields, to: metadata.tokenEndpoint).flatMap({ MCPOAuth.tokens($0) }) else {
            throw Failure(message: "“\(server.name)” did not give a token.")
        }
        save(MCPOAuth.Session(clientID: clientID, clientSecret: secret, tokenEndpoint: metadata.tokenEndpoint, resource: resourceID, scope: scope,
                              accessToken: tokens.access, refreshToken: tokens.refresh, expiresAt: tokens.expiresAt), for: server.name)
        Log.trace("MCP sign-in for \(server.name): done")
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await http.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: "HTTP error") }
        return data
    }

    /// The body of a 2xx answer, else nil.
    private func post(form fields: [(String, String)], to endpoint: String) async throws -> Data? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = MCPOAuth.form(fields)
        let (data, response) = try await http.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return nil }
        return data
    }

    nonisolated private static let page = """
        <!doctype html><meta charset="utf-8"><title>skil.li</title>
        <body style="font: 15px -apple-system, system-ui; text-align: center; padding-top: 18vh; color: #222">
        <h2>skil.li is signed in</h2><p>You can close this tab.</p></body>
        """
}

/// The browser's return, handed from the loopback server's thread.
private final class CallbackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (code: String?, state: String?, error: String?)?

    func deliver(_ value: (code: String?, state: String?, error: String?)) {
        lock.withLock { if result == nil { result = value } }
    }

    func wait(timeout: Duration) async -> (code: String?, state: String?, error: String?)? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let result = lock.withLock({ result }) { return result }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
