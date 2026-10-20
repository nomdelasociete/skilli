import CryptoKit
import Foundation

/// Signing in to an MCP server the way its authorization spec says: the
/// server answers 401 and points to its metadata (RFC 9728), that names the
/// authorization server (RFC 8414), skil.li registers itself as a client
/// (RFC 7591) and signs in with the authorization code and PKCE (RFC 7636),
/// asking for a token for this server only (RFC 8707). Pure parts here.
public enum MCPOAuth {
    /// What a 401's `WWW-Authenticate: Bearer …` points to.
    public static func challenge(_ header: String) -> (resourceMetadata: String?, scope: String?) {
        func value(_ key: String) -> String? {
            guard let range = header.range(of: "\(key)=\"") else { return nil }
            let rest = header[range.upperBound...]
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
        return (value("resource_metadata"), value("scope"))
    }

    /// RFC 9728's default: `https://host/.well-known/oauth-protected-resource/path`.
    public static func resourceMetadataURL(for server: URL) -> URL? {
        guard var parts = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        let path = parts.path == "/" ? "" : parts.path
        parts.path = "/.well-known/oauth-protected-resource" + path
        parts.query = nil
        return parts.url
    }

    /// Where an issuer's metadata may be (RFC 8414, then OpenID Connect).
    public static func serverMetadataURLs(issuer: URL) -> [URL] {
        guard var parts = URLComponents(url: issuer, resolvingAgainstBaseURL: false) else { return [] }
        let path = parts.path == "/" ? "" : parts.path
        parts.query = nil
        return ["/.well-known/oauth-authorization-server" + path, "/.well-known/openid-configuration" + path, path + "/.well-known/openid-configuration"]
            .compactMap { suffix in
                var url = parts
                url.path = suffix
                return url.url
            }
    }

    public struct ResourceMetadata: Decodable, Sendable {
        public let resource: String?
        public let authorizationServers: [String]?
        public let scopesSupported: [String]?

        enum CodingKeys: String, CodingKey {
            case resource
            case authorizationServers = "authorization_servers"
            case scopesSupported = "scopes_supported"
        }
    }

    public struct ServerMetadata: Decodable, Sendable {
        public let authorizationEndpoint: String
        public let tokenEndpoint: String
        public let registrationEndpoint: String?
        public let codeChallengeMethodsSupported: [String]?

        enum CodingKeys: String, CodingKey {
            case authorizationEndpoint = "authorization_endpoint"
            case tokenEndpoint = "token_endpoint"
            case registrationEndpoint = "registration_endpoint"
            case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        }
    }

    /// What is kept for a server, in the Keychain.
    public struct Session: Codable, Equatable, Sendable {
        public var clientID: String
        public var clientSecret: String?
        public var tokenEndpoint: String
        public var resource: String
        public var scope: String?
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?

        public init(clientID: String, clientSecret: String?, tokenEndpoint: String, resource: String, scope: String?,
                    accessToken: String, refreshToken: String?, expiresAt: Date?) {
            self.clientID = clientID
            self.clientSecret = clientSecret
            self.tokenEndpoint = tokenEndpoint
            self.resource = resource
            self.scope = scope
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        /// Expired, or within a minute of it: refreshed before use.
        public func needsRefresh(now: Date = .now) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSince(now) < 60
        }
    }

    /// A token endpoint's answer: the access token, maybe a new refresh
    /// token, how long it lasts.
    public static func tokens(_ data: Data, now: Date = .now) -> (access: String, refresh: String?, expiresAt: Date?)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty else { return nil }
        let seconds = (object["expires_in"] as? Double) ?? (object["expires_in"] as? String).flatMap(Double.init)
        return (access, object["refresh_token"] as? String, seconds.map { now.addingTimeInterval($0) })
    }

    /// A random code verifier: 43 to 128 unreserved characters.
    public static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return base64URL(Data(bytes))
    }

    /// S256: base64url(SHA-256(verifier)).
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func authorizationURL(endpoint: String, clientID: String, redirect: String, challenge: String,
                                        state: String, scope: String?, resource: String) -> URL? {
        guard var parts = URLComponents(string: endpoint) else { return nil }
        var items = parts.queryItems ?? []
        items += [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
                  URLQueryItem(name: "redirect_uri", value: redirect), URLQueryItem(name: "code_challenge", value: challenge),
                  URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "state", value: state),
                  URLQueryItem(name: "resource", value: resource)]
        if let scope, !scope.isEmpty { items.append(URLQueryItem(name: "scope", value: scope)) }
        parts.queryItems = items
        return parts.url
    }

    /// `application/x-www-form-urlencoded`, every value encoded.
    public static func form(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    /// The query of the redirect back: `code` and `state`, or `error`.
    public static func callback(_ target: String) -> (code: String?, state: String?, error: String?) {
        let items = URLComponents(string: "http://localhost" + target)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return (value("code"), value("state"), value("error_description") ?? value("error"))
    }

    /// Only https, or plain http to this Mac.
    public static func isAllowed(_ address: String) -> Bool {
        guard let url = URL(string: address), let host = url.host else { return false }
        return url.scheme == "https" || url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
