import Combine
import Foundation

public struct RelayHTTPReply: Sendable {
    let status: Int
    let data: Data
    /// The relay's `Retry-After`, in seconds (429, 503).
    var retryAfter: TimeInterval? = nil
}

public struct RelayDeviceAPI: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> RelayHTTPReply
    let origin: URL
    public init(origin: URL, send: Send? = nil) { self.origin = origin; if let send { self.send = send } }
    public var send: Send = { request in
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 30
        settings.timeoutIntervalForResource = 30
        let session = URLSession(configuration: settings, delegate: RelayNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard data.count <= RelayInbox.maximumBody else { throw URLError(.dataLengthExceedsMaximum) }
        return RelayHTTPReply(status: response.statusCode, data: data,
                              retryAfter: RelayInbox.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
    }

    func post(_ path: String, body: [String: String]? = nil, access: String? = nil) async throws -> RelayHTTPReply {
        var request = URLRequest(url: origin.appendingPathComponent(path))
        request.httpMethod = "POST"
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let access { request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization") }
        return try await send(request)
    }
}

struct RelayDeviceGrant: Decodable {
    let device_code: String
    let verification_uri: URL
    let expires_in: TimeInterval

    var isValid: Bool {
        !device_code.isEmpty && expires_in > 0 && expires_in <= 600 &&
        verification_uri.scheme == "https" && verification_uri.host != nil &&
        verification_uri.user == nil && verification_uri.password == nil
    }
}

struct RelayTokenPair: Codable, Equatable {
    let access_token: String
    let refresh_token: String
    let expires_in: TimeInterval
    let computer_id: String
    var installations: [String]?

    var isValid: Bool {
        access_token.hasPrefix("v2.") && !access_token.contains(where: \.isWhitespace) &&
        !refresh_token.isEmpty && !refresh_token.contains(where: \.isWhitespace) &&
        !computer_id.isEmpty && expires_in > 0 && expires_in <= 900
    }
}

struct RelayDeviceCredentials: Codable {
    let origin: String
    var pair: RelayTokenPair
    var expiresAt: Date
    // Durable retry state survives network failure and process restart.
    var requiresEnrollment = false
    var authorityOrigin: String? = nil
    var pendingRefreshID: String? = nil
    var pendingRevocation: Bool? = nil
}

@MainActor
public final class RelayDeviceSession: ObservableObject {
    static let account = "relay-device-v2"
    @Published public private(set) var message: String?
    @Published public private(set) var isBusy = false
    @Published public private(set) var isEnrolling = false
    @Published private(set) var credentials: RelayDeviceCredentials?
    private(set) var hasSavedEnrollment = false
    private(set) var legacyExpired = false
    private var retryDelay: TimeInterval = 30
    private var retryNotBefore: Date?
    private var rejectedAccess = false
    public var githubToken: () -> String? = { nil }
    private var verifiedNativeToken: String?
    private var verifiedAccessToken: String?
    /// The numeric GitHub id both GitHub (native token) and the authority
    /// agreed on; server inbox snapshots must carry it.
    public private(set) var verifiedSubject: String?
    private var identityGeneration = 0
    private var identityTask: Task<Void, Never>?
    private var identityTarget: String?
    private var identityNative: String?
    private var active = false
    private var activeOrigin = ""
    private var timer: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private let appID: String
    private var readUnavailable = false
    private let read: () throws -> String?
    private let save: (String) throws -> Void
    private let legacy: () -> String?
    private let send: RelayDeviceAPI.Send
    private let openBrowser: (URL) -> Bool
    private let authorityOrigin: () -> String
    private let browserOrigin: () -> String
    private let sleep: (TimeInterval) async throws -> Void
    public var onChange: (() -> Void)?

    public init(appID: String,
         read: @escaping () throws -> String?,
         save: @escaping (String) throws -> Void,
         legacy: @escaping () -> String?,
         send: @escaping RelayDeviceAPI.Send = RelayDeviceAPI(origin: URL(string: "https://localhost")!).send,
         openBrowser: @escaping (URL) -> Bool,
         authorityOrigin: @escaping () -> String,
         browserOrigin: @escaping () -> String,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.appID = appID
        self.read = read
        self.save = save
        self.legacy = legacy
        self.send = send
        self.openBrowser = openBrowser
        self.authorityOrigin = authorityOrigin
        self.browserOrigin = browserOrigin
        self.sleep = sleep
        restoreCredentials()
    }

    private func restoreCredentials() {
        let stored: String?
        do { stored = try read() }
        catch {
            readUnavailable = true
            hasSavedEnrollment = true
            message = "Keychain is temporarily unavailable. Live access will retry automatically."
            return
        }
        readUnavailable = false
        do {
            credentials = nil
            hasSavedEnrollment = stored != nil
            message = nil
            if let stored {
                hasSavedEnrollment = true
                credentials = try JSONDecoder().decode(RelayDeviceCredentials.self, from: Data(stored.utf8))
                guard credentials?.pair.isValid == true else {
                    credentials = nil
                    throw URLError(.cannotDecodeContentData)
                }
                if credentials?.authorityOrigin == nil { credentials?.requiresEnrollment = true }
                if credentials?.requiresEnrollment == true { message = "Authorize this Mac again to restore live updates." }
            }
        } catch {
            hasSavedEnrollment = true
            message = "Could not read this Mac’s authorization from Keychain. Authorize again to restore live updates."
        }
    }

    public var needsEnrollment: Bool { hasSavedEnrollment && (credentials == nil || credentials?.requiresEnrollment == true) }
    public var installationCount: Int { credentials?.pair.installations?.count ?? 0 }
    public var canRevoke: Bool { credentials != nil && credentials?.requiresEnrollment == false }

    public func configuration(origin: String) -> RelayDeviceConfiguration? {
        guard let url = Self.origin(origin), let native = githubToken(),
              native == verifiedNativeToken, credentials?.pair.access_token == verifiedAccessToken else { return nil }
        if hasSavedEnrollment {
            guard !rejectedAccess, let credentials, !credentials.requiresEnrollment,
                  credentials.pendingRefreshID == nil, credentials.origin == url.absoluteString,
                  credentials.expiresAt > Date() else { return nil }
            return RelayDeviceConfiguration(origin: origin, token: credentials.pair.access_token)
        }
        return nil // Legacy tokens carry no verifiable GitHub identity.
    }

    /// What the server inbox needs, only once this Mac's relay access and
    /// its GitHub identity are verified: the authority, the browser origin
    /// its authorization page must be on, the access token, the subject.
    public func inboxAccess(origin: String) -> RelayInboxAccess? {
        guard let configuration = configuration(origin: origin), let subject = verifiedSubject,
              let authority = Self.origin(credentials?.authorityOrigin ?? ""), authority == Self.origin(authorityOrigin()),
              let browser = Self.origin(browserOrigin()) else { return nil }
        return RelayInboxAccess(authority: authority, browser: browser, token: configuration.token, subject: subject, send: send)
    }

    public static func origin(_ value: String) -> URL? {
        guard let config = RelayDeviceConfiguration(origin: value, token: "v2.validation") else { return nil }
        var components = URLComponents(url: config.origin, resolvingAgainstBaseURL: false)
        components?.path = ""
        return components?.url
    }

    public func activate(origin: String) {
        active = true
        activeOrigin = origin
        if readUnavailable { restoreCredentials() }
        scheduleRenewal()
        verifyRestoredIdentity()
    }

    public func suspend() {
        active = false
        identityGeneration += 1
        identityTask?.cancel()
        identityTask = nil
        verifiedNativeToken = nil
        verifiedAccessToken = nil
        verifiedSubject = nil
        timer?.cancel()
        timer = nil
        // Do not cancel a rotation that may already have consumed its token.
    }

    private func persist(_ value: RelayDeviceCredentials) throws {
        let data = try JSONEncoder().encode(value)
        try save(String(decoding: data, as: UTF8.self))
        credentials = value
        hasSavedEnrollment = true
    }

    public func enroll(origin: String) {
        guard let enrollmentToken = githubToken(), !enrollmentToken.isEmpty,
              !isBusy, !readUnavailable, credentials?.pendingRevocation != true, let url = Self.origin(origin),
              let authority = Self.origin(authorityOrigin()), let browser = Self.origin(browserOrigin()),
              authority != url, browser != url else { return }
        isBusy = true
        isEnrolling = true
        identityTask?.cancel()
        identityTask = nil
        identityGeneration += 1
        let enrollmentGeneration = identityGeneration
        message = "Checking whether live update setup is available…"
        operation = Task { [self] in
            defer {
                isBusy = false
                isEnrolling = false
                operation = nil
                scheduleRenewal()
                verifyRestoredIdentity()
            }
            let api = RelayDeviceAPI(origin: authority, send: send)
            do {
                try Task.checkCancellation()
                let startedAt = Date()
                let reply = try await api.post("devices", body: ["app": appID])
                guard reply.status == 201 else {
                    switch reply.status {
                    case 404, 503: message = "Live update setup is not available yet. Your existing connection is unchanged."
                    case 429: message = "Too many setup attempts. Wait before trying again."
                    default: message = "Could not start setup. Your existing connection is unchanged."
                    }
                    return
                }
                try Task.checkCancellation()
                let grant = try JSONDecoder().decode(RelayDeviceGrant.self, from: reply.data)
                guard grant.isValid, grant.verification_uri.scheme == browser.scheme,
                      grant.verification_uri.host == browser.host, grant.verification_uri.port == browser.port,
                      grant.verification_uri.path == "/enroll", grant.verification_uri.fragment == nil else { throw URLError(.badServerResponse) }
                let deadline = startedAt.addingTimeInterval(grant.expires_in)
                guard deadline > Date(), openBrowser(grant.verification_uri) else { throw URLError(.cannotLoadFromNetwork) }
                message = "Finish authorizing this Mac in your browser."
                while Date() < deadline {
                    try await sleep(5)
                    guard Date() < deadline else { break }
                    let result = try await api.post("devices/token", body: ["device_code": grant.device_code])
                    if result.status == 202 { continue }
                    guard result.status == 200 else {
                        message = result.status == 401 ? "Authorization expired or was refused. Start setup again." : "Setup could not finish. Start again when the service is available."
                        return
                    }
                    let pair = try JSONDecoder().decode(RelayTokenPair.self, from: result.data)
                    guard pair.isValid, let installations = pair.installations, !installations.isEmpty,
                          installations.allSatisfy(Self.numericID) else { throw URLError(.badServerResponse) }
                    try Task.checkCancellation()
                    guard githubToken() == enrollmentToken,
                          let verified = await verifyIdentity(pair: pair, authority: authority) else { return }
                    let native = verified.native
                    try Task.checkCancellation()
                    guard identityGeneration == enrollmentGeneration, githubToken() == native else { return }
                    // One atomic Keychain item holds both tokens. Never overwrite the legacy item.
                    try persist(RelayDeviceCredentials(origin: url.absoluteString, pair: pair,
                        expiresAt: Date().addingTimeInterval(pair.expires_in), authorityOrigin: authority.absoluteString))
                    verifiedNativeToken = native
                    verifiedAccessToken = pair.access_token
                    verifiedSubject = verified.subject
                    rejectedAccess = false
                    retryNotBefore = nil
                    message = "This Mac is authorized for \(installations.count) GitHub account(s). Live access renews automatically."
                    onChange?()
                    return
                }
                message = "Authorization expired. Start setup again."
            } catch {
                message = Task.isCancelled
                    ? "Setup cancelled. Your existing connection is unchanged."
                    : "Setup could not finish. Your existing connection is unchanged; you can start again."
            }
        }
    }

    private func verifyRestoredIdentity() {
        guard active, !isEnrolling, let current = credentials,
              !current.requiresEnrollment, current.pendingRevocation != true,
              current.expiresAt > Date(),
              let authority = Self.origin(current.authorityOrigin ?? ""),
              authority == Self.origin(authorityOrigin()), let native = githubToken(),
              verifiedNativeToken != native || verifiedAccessToken != current.pair.access_token else { return }
        if identityTask != nil, identityTarget == current.pair.access_token, identityNative == native { return }
        identityTask?.cancel()
        identityGeneration += 1
        let generation = identityGeneration
        identityTarget = current.pair.access_token
        identityNative = native
        identityTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.identityGeneration == generation { self.identityTask = nil }
            }
            if let verified = await self.verifyIdentity(pair: current.pair, authority: authority),
               !Task.isCancelled, self.active, self.githubToken() == verified.native,
               self.identityGeneration == generation,
               self.credentials?.pair.access_token == current.pair.access_token,
               self.credentials?.requiresEnrollment == false {
                self.verifiedNativeToken = verified.native
                self.verifiedAccessToken = current.pair.access_token
                self.verifiedSubject = verified.subject
                self.message = "GitHub account verified for live updates."
                self.onChange?()
            }
        }
    }

    // Compare stable GitHub numeric IDs obtained independently from GitHub and
    // the authenticated authority. Never trust a browser login name or local ID.
    private func verifyIdentity(pair: RelayTokenPair, authority: URL) async -> (native: String, subject: String)? {
        guard let native = githubToken(), !native.isEmpty else { return nil }
        let generation = identityGeneration
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
            request.setValue("Bearer \(native)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Skilli", forHTTPHeaderField: "User-Agent")
            let userReply = try await send(request)
            struct User: Decodable { let id: Int64 }
            guard userReply.status == 200 else { throw URLError(.userAuthenticationRequired) }
            let user = try JSONDecoder().decode(User.self, from: userReply.data)
            let reply = try await RelayDeviceAPI(origin: authority, send: send)
                .post("computers/identity", access: pair.access_token)
            struct Identity: Decodable { let subject: String }
            guard reply.status == 200 else { throw URLError(.userAuthenticationRequired) }
            let identity = try JSONDecoder().decode(Identity.self, from: reply.data)
            try Task.checkCancellation()
            guard githubToken() == native, generation == identityGeneration else { return nil }
            guard user.id > 0, identity.subject == String(user.id) else {
                message = "Live updates use a different GitHub account. Authorize this Mac again using the same account as the app."
                return nil
            }
            return (native, identity.subject)
        } catch {
            if !Task.isCancelled, generation == identityGeneration {
                message = "Could not verify the GitHub account for live updates. Periodic GitHub checks continue; try authorizing again."
            }
            return nil
        }
    }

    public func cancelEnrollment() {
        guard isEnrolling else { return }
        operation?.cancel()
    }

    public func accessExpired() {
        guard hasSavedEnrollment else {
            // v1 cannot be renewed. Keep its Keychain item, but stop reconnecting it.
            legacyExpired = true
            message = "Legacy live access has expired. Authorize this Mac when setup becomes available."
            onChange?()
            return
        }
        rejectedAccess = true
        onChange?()
        renew()
    }

    private func scheduleRenewal() {
        timer?.cancel()
        timer = nil
        guard active, !isBusy else { return }
        if readUnavailable {
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.restoreCredentials()
                self.onChange?()
                self.scheduleRenewal()
            }
            return
        }
        if credentials?.pendingRevocation == true {
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(self?.retryDelay ?? 30)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.revoke()
            }
            return
        }
        guard let credentials, !credentials.requiresEnrollment,
              Self.origin(activeOrigin)?.absoluteString == credentials.origin,
              Self.origin(authorityOrigin())?.absoluteString == credentials.authorityOrigin else { return }
        let delay: TimeInterval
        if let retryNotBefore {
            delay = max(1, retryNotBefore.timeIntervalSinceNow)
        } else if credentials.pendingRefreshID != nil {
            delay = retryDelay
        } else {
            delay = max(1, credentials.expiresAt.timeIntervalSinceNow - min(60, credentials.pair.expires_in / 2))
        }
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.renew()
        }
    }

    public func renew() {
        guard !isBusy, credentials?.requiresEnrollment == false else { return }
        guard retryNotBefore == nil || retryNotBefore! <= Date() else {
            scheduleRenewal()
            return
        }
        isBusy = true
        timer?.cancel()
        operation = Task { [self] in
            defer { isBusy = false; operation = nil; scheduleRenewal() }
            _ = await rotate()
        }
    }

    private func rotate() async -> Bool {
        guard var old = credentials, !old.requiresEnrollment,
              let url = Self.origin(old.authorityOrigin ?? ""),
              url == Self.origin(authorityOrigin()) else { return false }
        do {
            if old.pendingRefreshID == nil {
                old.pendingRefreshID = UUID().uuidString
                // Persist the idempotency key before sending. A restart retries
                // the exact same rotation instead of replaying it as a new one.
                try persist(old)
            }
            let result = try await RelayDeviceAPI(origin: url, send: send).post("tokens/refresh",
                body: ["refresh_token": old.pair.refresh_token, "request_id": old.pendingRefreshID!])
            if result.status == 401 {
                old.requiresEnrollment = true
                old.pendingRefreshID = nil
                try persist(old)
                message = "Live authorization was revoked or expired. Authorize this Mac again."
                onChange?()
                return false
            }
            guard result.status == 200 else { throw URLError(.badServerResponse) }
            var pair = try JSONDecoder().decode(RelayTokenPair.self, from: result.data)
            guard pair.isValid, pair.computer_id == old.pair.computer_id else { throw URLError(.badServerResponse) }
            pair.installations = old.pair.installations
            try persist(RelayDeviceCredentials(origin: old.origin, pair: pair,
                expiresAt: Date().addingTimeInterval(pair.expires_in), authorityOrigin: old.authorityOrigin))
            retryDelay = 30
            retryNotBefore = nil
            rejectedAccess = false
            message = "Live access renewed automatically."
            verifyRestoredIdentity()
            onChange?()
            return true
        } catch {
            retryDelay = min(300, retryDelay * 2)
            retryNotBefore = Date().addingTimeInterval(retryDelay)
            message = "Live renewal is temporarily unavailable. Retrying automatically; polling continues."
            onChange?()
            return false
        }
    }

    public func revoke() {
        guard !isBusy, let current = credentials,
              !current.requiresEnrollment || current.pendingRevocation == true else { return }
        isBusy = true
        timer?.cancel()
        operation = Task { [self] in
            defer { isBusy = false; operation = nil; scheduleRenewal() }
            guard var old = credentials,
                  let url = Self.origin(old.authorityOrigin ?? ""),
                  url == Self.origin(authorityOrigin()) else { return }
            do {
                old.requiresEnrollment = true
                old.pendingRevocation = true
                try persist(old)
                onChange?()
                let result = try await RelayDeviceAPI(origin: url, send: send).post("computers/revoke",
                    body: ["refresh_token": old.pair.refresh_token])
                guard result.status == 204 || result.status == 401 else { throw URLError(.badServerResponse) }
                old.pendingRevocation = nil
                old.pendingRefreshID = nil
                try persist(old)
                message = result.status == 204
                    ? "This Mac’s live authorization was revoked."
                    : "This authorization is no longer valid. You can authorize this Mac again."
            } catch {
                retryDelay = min(300, retryDelay * 2)
                message = "Server revocation is pending. Retrying automatically."
                onChange?()
            }
        }
    }

    private static func numericID(_ value: String) -> Bool {
        !value.isEmpty && value.first != "0" && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

public struct RelayDeviceConfiguration {
    public let origin: URL
    public let token: String
    public init?(origin: String, token: String?) {
        guard let url = RelayAddress.origin(origin), let token, RelayToken.accepts(token) else { return nil }
        self.origin = url
        self.token = token
    }
}
