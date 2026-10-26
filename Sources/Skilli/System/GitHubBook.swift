import AppKit
import Network
import SkilliCore

/// Where GitHub is: github.com, or the self-test's stand-in.
struct GitHubEndpoints: Sendable {
    var api = URL(string: "https://api.github.com")!
    var web = URL(string: "https://github.com")!
}

/// The OAuth app skil.li signs in with ("skil.li", owned by nomdelasociete,
/// device flow on, tokens that do not expire): its public client id, not a
/// secret. `GITHUB_OAUTH_CLIENT_ID` overrides it while developing.
enum GitHubOAuth {
    static let publishedClientID = "Ov23liBagRcrC6sSn3XV"
    /// Pull requests in private repositories, the notifications, the login.
    static let scopes = "repo notifications read:user"

    static var clientID: String {
        let override = ProcessInfo.processInfo.environment["GITHUB_OAUTH_CLIENT_ID"] ?? ""
        return override.isEmpty ? publishedClientID : override
    }
}

/// The code the user types on github.com to let skil.li in.
struct GitHubDeviceCode: Sendable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    var interval: TimeInterval
}

struct GitHubError: LocalizedError {
    let message: String
    /// GitHub asked to wait (rate limit) until then.
    var retryAfter: Date?
    /// The token is not valid any more: sign in again.
    var signedOut = false
    var errorDescription: String? { message }
}

/// Talks to GitHub with the user's token. Pull requests in one GraphQL
/// request; notifications asked with `If-Modified-Since`, so an unchanged
/// answer (304) costs nothing.
actor GitHubClient {
    let endpoints: GitHubEndpoints
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init(endpoints: GitHubEndpoints) {
        self.endpoints = endpoints
    }

    enum NotificationsAnswer: Sendable {
        case unchanged(pollInterval: TimeInterval)
        case changed([GitHubNotification], lastModified: String?, pollInterval: TimeInterval)
    }

    func inbox(token: String) async throws -> (login: String, pullRequests: [PullRequest]) {
        let body: [String: Any] = ["query": GitHubInbox.query, "variables": ["reviewRequested": GitHubInbox.reviewRequestedSearch]]
        var request = Self.request(endpoints.api.appendingPathComponent("graphql"), "POST", token: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await send(request)
        do {
            return try GitHubInbox.pullRequests(fromResponse: data)
        } catch let failure as GitHubInbox.Failure {
            throw GitHubError(message: failure.message)
        }
    }

    func notifications(token: String, since lastModified: String?) async throws -> NotificationsAnswer {
        var components = URLComponents(url: endpoints.api.appendingPathComponent("notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "50")]
        var request = Self.request(components.url!, "GET", token: token)
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await send(request, notModifiedIsFine: true)
        let interval = TimeInterval(Self.header("X-Poll-Interval", in: response) ?? "") ?? 60
        if response.statusCode == 304 { return .unchanged(pollInterval: interval) }
        return .changed(try GitHubNotifications.parse(data), lastModified: Self.header("Last-Modified", in: response), pollInterval: interval)
    }

    func merge(_ pullRequest: PullRequest, token: String) async throws {
        guard let method = pullRequest.defaultMergeMethod else { throw GitHubError(message: "You may not merge this pull request.") }
        var request = Self.request(endpoints.api.appendingPathComponent("repos/\(pullRequest.repositoryFullName)/pulls/\(pullRequest.number)/merge"),
                                   "PUT", token: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sha": pullRequest.headSHA, "merge_method": method.rawValue])
        let (data, _) = try await send(request)
        let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard answer?["merged"] as? Bool == true else {
            throw GitHubError(message: answer?["message"] as? String ?? "GitHub did not merge it.")
        }
    }

    func updateBranch(_ pullRequest: PullRequest, token: String) async throws {
        var request = Self.request(
            endpoints.api.appendingPathComponent("repos/\(pullRequest.repositoryFullName)/pulls/\(pullRequest.number)/update-branch"),
            "PUT", token: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expected_head_sha": pullRequest.headSHA])
        _ = try await send(request)
    }

    func markRead(_ id: String, token: String) async throws {
        _ = try await send(Self.request(endpoints.api.appendingPathComponent("notifications/threads/\(id)"), "PATCH", token: token))
    }

    // MARK: Signing in (GitHub's device flow)

    func startSignIn(clientID: String) async throws -> GitHubDeviceCode {
        let data = try await form(endpoints.web.appendingPathComponent("login/device/code"), ["client_id": clientID, "scope": GitHubOAuth.scopes])
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any], let deviceCode = answer["device_code"] as? String,
              let userCode = answer["user_code"] as? String, let page = (answer["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw GitHubError(message: "GitHub did not give a sign-in code.")
        }
        return GitHubDeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURL: page,
                                expiresAt: .now.addingTimeInterval(TimeInterval(answer["expires_in"] as? Int ?? 900)),
                                interval: TimeInterval(answer["interval"] as? Int ?? 5))
    }

    /// Asks every `interval` (GitHub's pace) until the user has typed the
    /// code; the token.
    func waitForToken(_ code: GitHubDeviceCode, clientID: String) async throws -> String {
        var code = code
        while Date.now < code.expiresAt {
            try await Task.sleep(for: .seconds(code.interval))
            let data = try await form(endpoints.web.appendingPathComponent("login/oauth/access_token"),
                                      ["client_id": clientID, "device_code": code.deviceCode,
                                       "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let token = answer["access_token"] as? String, !token.isEmpty { return token }
            switch answer["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": code.interval += 5
            case "expired_token": throw GitHubError(message: "The code expired. Sign in again.")
            case "access_denied": throw GitHubError(message: "GitHub sign-in was cancelled.")
            case let error: throw GitHubError(message: answer["error_description"] as? String ?? error ?? "GitHub did not sign you in.")
            }
        }
        throw GitHubError(message: "The code expired. Sign in again.")
    }

    // MARK: HTTP

    private func form(_ url: URL, _ values: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(values.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $1)" }
            .joined(separator: "&").utf8)
        return try await send(request).data
    }

    private func send(_ request: URLRequest, notModifiedIsFine: Bool = false) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError(message: "GitHub did not answer.") }
        if (200..<300).contains(http.statusCode) || (notModifiedIsFine && http.statusCode == 304) { return (data, http) }
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        var error = GitHubError(message: "GitHub: \(message)")
        error.signedOut = http.statusCode == 401
        let limited = http.statusCode == 429 || (http.statusCode == 403 && message.localizedCaseInsensitiveContains("rate limit"))
        if limited {
            error.retryAfter = Self.header("Retry-After", in: http).flatMap(TimeInterval.init).map { Date.now.addingTimeInterval($0) }
                ?? Self.header("X-RateLimit-Reset", in: http).flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
                ?? .now.addingTimeInterval(15 * 60)
        }
        throw error
    }

    private static func request(_ url: URL, _ method: String, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("skil.li", forHTTPHeaderField: "User-Agent")
        if method != "GET" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: name)
    }
}

/// The user's GitHub in skil.li: signed in with the device flow (the token
/// in the Keychain), their pull requests in four groups and their
/// notifications. Kept fresh only while something shows them (the strip
/// under the search field): nothing asks GitHub otherwise. Then one timer:
/// every 15 s while checks run or just after a change, else every minute;
/// notifications at GitHub's pace, free when nothing changed. With a relay
/// origin and a sealed stream token, the strip or GitHub mode holds one
/// stream instead: a connect or a wake reads pull requests at once, and the
/// inbox timer runs only while that stream is down. Notifications stay a
/// local poll. With server sync on (the user's consent, then a separate
/// authorization in the browser), every read of pull requests and
/// notifications goes to the relay's copy instead (`GitHubServerInbox`):
/// this Mac's GitHub token only acts (merge, update a branch, mark read),
/// and a relay that cannot answer is said, never read around.
@MainActor
@Observable
final class GitHubBook {
    private(set) var pullRequests: [PullRequest] = []
    private(set) var notifications: [GitHubNotification] = []
    private(set) var login: String?
    /// The last refresh's problem, said in Settings and the launcher.
    private(set) var problem: String?
    private(set) var lastRefresh: Date?
    /// While signing in: the code to type on github.com.
    private(set) var signInCode: GitHubDeviceCode?
    private(set) var signInProblem: String?
    /// The relay refused the sealed token. The GitHub poll keeps going.
    private(set) var relayProblem: String?
    private(set) var hasRelayToken = false
    /// Server sync's state while it is on: what holds it back.
    private(set) var serverHold: GitHubServerHold?
    /// False when GitHub had more unread notifications than the relay keeps.
    private(set) var notificationsComplete = true

    /// Changed (the strip and the GitHub mode redraw).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Keep the data fresh in the background (Settings → GitHub: under the
    /// search field).
    @ObservationIgnored var keepsFresh = false {
        didSet {
            guard keepsFresh != oldValue else { return }
            keepsFresh ? refresh(force: true) : schedule()
            syncRelay()
        }
    }
    /// GitHub mode is on screen. The stream stays up with the strip or this.
    @ObservationIgnored var showsGitHub = false {
        didSet { if showsGitHub != oldValue { syncRelay(); schedule() } }
    }
    /// Settings → GitHub is open: this Mac's relay identity is checked so
    /// server sync can be turned on, without opening the stream.
    @ObservationIgnored var showsSettings = false {
        didSet { if showsSettings != oldValue { syncRelay() } }
    }
    /// Settings → GitHub → Server sync. On: pull requests and notifications
    /// are read from the relay only. What was read the other way goes.
    @ObservationIgnored var serverSync = false {
        didSet {
            guard serverSync != oldValue else { return }
            Log.actions.notice("GitHub: server sync \(self.serverSync ? "on" : "off")")
            clearReadData()
            relayEndpoint = nil
            syncRelay()
            refresh(force: true)
            onChange?()
        }
    }
    /// Relay origin from Settings. Empty leaves the timer as it is.
    /// `RELAY_PUBLIC_URL` overrides it.
    @ObservationIgnored var relayPublicURL = "" {
        didSet { if relayPublicURL != oldValue { syncRelay() } }
    }
    /// Self-test hook: links open here instead.
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    @ObservationIgnored private let client: GitHubClient
    @ObservationIgnored private let keychainAccount: String
    @ObservationIgnored private let clientID: () -> String
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var accountGeneration = UUID()
    @ObservationIgnored private var lastModified: String?
    @ObservationIgnored private var pollInterval: TimeInterval = 60
    @ObservationIgnored private var nextNotifications = Date.distantPast
    @ObservationIgnored private var busyUntil: Date?
    @ObservationIgnored private var lastAttempt = Date.distantPast
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var signingIn: Task<Void, Never>?
    @ObservationIgnored private var signInRequestID: UUID?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeUntil = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private var online = true
    @ObservationIgnored private let relayAccount: String
    @ObservationIgnored private var relayToken: String?
    @ObservationIgnored let relayDevice: RelayDeviceSession
    @ObservationIgnored private let relay = RelayConnection()
    @ObservationIgnored private var relayCoalescer = RelayCoalescer()
    @ObservationIgnored private var relayEndpoint: String?
    @ObservationIgnored private var relayEndpointInbox = false
    @ObservationIgnored let server = GitHubServerInbox(client: { nil })

    private static let minimumSpacing: TimeInterval = 15
    private static let activeSpacing: TimeInterval = 15
    private static let idleSpacing: TimeInterval = 60
    private static let activeWindow: TimeInterval = 2 * 60

    /// `keychainPrefix`: the self-test keeps its own token.
    init(endpoints: GitHubEndpoints = GitHubEndpoints(), keychainPrefix: String = "", clientID: @escaping () -> String = { GitHubOAuth.clientID }) {
        client = GitHubClient(endpoints: endpoints)
        keychainAccount = keychainPrefix + "github-token"
        relayAccount = keychainPrefix + "relay-token"
        let deviceAccount = keychainPrefix + "relay-device-v2"
        let legacyAccount = keychainPrefix + "relay-token"
        relayDevice = RelayDeviceSession(appID: "5332414",
            read: { try RelayCredentialVault.read(deviceAccount) },
            save: { try RelayCredentialVault.save($0, account: deviceAccount) },
            legacy: { Keychain.read(account: legacyAccount) },
            openBrowser: { NSWorkspace.shared.open($0) },
            authorityOrigin: { "https://access.relay.nomdelasociete.com" },
            browserOrigin: { "https://auth.relay.nomdelasociete.com" })
        self.clientID = clientID
        token = Keychain.read(account: keychainAccount)
        relayToken = Keychain.read(account: relayAccount)
        hasRelayToken = relayToken.map(RelayToken.accepts) ?? false
        relayDevice.githubToken = { [weak self] in self?.token }
        relayDevice.onChange = { [weak self] in
            guard let self else { return }
            self.relayProblem = self.relayDevice.message
            self.relayEndpoint = nil
            self.syncRelay()
            if self.serverSync { self.refresh(force: true) }
            self.schedule()
            self.onChange?()
        }
        server.client = { [weak self] in self?.serverAccess().map(RelayInboxClient.init(access:)) }
        server.onChange = { [weak self] in self?.applyServer() }
        server.onDeviceExpired = { [weak self] in self?.relayDevice.accessExpired() }
        relay.onConnect = { [weak self] in
            guard let self else { return }
            self.relayProblem = nil
            self.noteRelay()
            if self.serverSync { self.server.readNotifications() }
            self.schedule()
        }
        relay.onWake = { [weak self] in self?.noteRelay() }
        relay.onDrop = { [weak self] in self?.schedule() }
        relay.onRejected = { [weak self] in
            guard let self else { return }
            self.relayDevice.accessExpired()
            self.relayProblem = self.relayDevice.message
            self.relayEndpoint = nil
            self.schedule()
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconnectRelay()
                self?.refresh(force: true)
            }
        })
        network.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                guard let self, up != self.online else { return }
                self.online = up
                if up {
                    self.reconnectRelay()
                    self.refresh(force: true)
                }
            }
        }
        network.start(queue: .main)
    }

    var isSignedIn: Bool { token != nil }
    /// Signing in is possible in this build (the OAuth app's id is in).
    var canSignIn: Bool { !clientID().isEmpty }

    /// Pull requests first (ready, blocked, waiting, testing), then unread
    /// notifications; the launcher's GitHub mode and the agents' lists.
    var unreadNotifications: [GitHubNotification] { notifications.filter(\.unread) }

    // MARK: Refreshing

    /// Reads GitHub again, unless it was read in the last 15 s (`force`
    /// skips that, never GitHub's own wait). `inbox: false` is the
    /// notification poll while the relay stream is up: pull requests wait
    /// for a wake.
    func refresh(force: Bool = false, inbox: Bool = true) {
        guard let token else { return schedule() }
        // Server sync: the relay's copy, whatever happens to the relay.
        if serverSync { return refreshServer(force: force, inbox: inbox) }
        if let busyUntil, busyUntil > .now { return schedule() }
        if inbox {
            guard force || Date.now.timeIntervalSince(lastAttempt) >= Self.minimumSpacing, refreshing == nil else { return }
            lastAttempt = .now
        } else {
            guard refreshing == nil, Date.now >= nextNotifications else { return schedule() }
        }
        let askNotifications = !inbox || force || Date.now >= nextNotifications
        let since = lastModified
        let generation = accountGeneration
        refreshing = Task { [client] in
            defer {
                if accountGeneration == generation {
                    refreshing = nil
                    if relayCoalescer.finished() {
                        refresh(force: true)
                        if refreshing == nil {
                            _ = relayCoalescer.finished()
                            schedule()
                        }
                    } else {
                        schedule()
                    }
                }
            }
            do {
                // Server sync turned on meanwhile: this Mac reads nothing.
                guard !serverSync else { return }
                let inboxResult: (login: String, pullRequests: [PullRequest])?
                if inbox {
                    inboxResult = try await client.inbox(token: token)
                } else {
                    inboxResult = nil
                }
                // Again after the first read: server sync may have come on during it.
                guard accountGeneration == generation, !serverSync, !Task.isCancelled else { return }
                let answer = askNotifications ? try await client.notifications(token: token, since: since) : nil
                guard accountGeneration == generation, !Task.isCancelled else { return }
                apply(login: inboxResult?.login, pullRequests: inboxResult?.pullRequests, notifications: answer)
            } catch let error as GitHubError {
                guard accountGeneration == generation, !Task.isCancelled else { return }
                failed(error)
            } catch {
                guard accountGeneration == generation, !Task.isCancelled else { return }
                failed(GitHubError(message: error.localizedDescription))
            }
        }
    }

    /// Reads the relay's copy: pull requests unless read in the last 15 s
    /// (`force`: a wake, sign-in, the network back), notifications at the
    /// relay's pace. Each waits for the relay's `Retry-After`.
    private func refreshServer(force: Bool, inbox: Bool) {
        if inbox, force || Date.now.timeIntervalSince(server.lastInboxRead ?? .distantPast) >= Self.minimumSpacing {
            server.readInbox()
        }
        server.readNotifications()
        schedule()
    }

    /// What kept this kind from being read again, for an agent's list.
    func problem(notifications: Bool) -> String? {
        guard serverSync else { return problem }
        return (notifications ? server.notificationsHold : server.inboxHold)?.message
    }

    /// Settings → Read Now: the relay reads GitHub again (spaced and
    /// limited there).
    func readNow() {
        guard serverSync else { return refresh(force: true) }
        guard isSignedIn else { return }
        server.readInbox(refresh: true)
        server.readNotifications(refresh: true)
    }

    private func applyServer() {
        guard serverSync else { return }
        pullRequests = server.pullRequests ?? []
        notifications = server.notifications ?? []
        notificationsComplete = server.notificationsComplete
        if let login = server.login { self.login = login }
        serverHold = server.hold
        problem = server.hold?.message
        lastRefresh = server.lastInboxRead
        if server.pullRequests != nil { Log.trace("GitHub (relay): \(GitHubInbox.summary(pullRequests)), \(unreadNotifications.count) unread") }
        schedule()
        onChange?()
    }

    /// This Mac's way to the relay's inbox, once signed in and verified.
    private func serverAccess() -> RelayInboxAccess? {
        guard isSignedIn, let origin = resolvedRelayOrigin else { return nil }
        return relayDevice.inboxAccess(origin: origin.absoluteString)
    }

    /// Server sync can be authorized now (this Mac's relay identity checked).
    var canAuthorizeServerSync: Bool { serverAccess() != nil }

    /// Server sync was just turned on: when the user's other Mac already
    /// authorized it, the relay answers at once and nothing opens; else the
    /// browser, for the grant.
    func startServerSync() async throws {
        guard let access = serverAccess() else {
            throw GitHubError(message: "Authorize this Mac for live updates first.")
        }
        do {
            _ = try await RelayInboxClient(access: access).inbox()
            return
        } catch RelayInboxFailure.authorizationRequired {
        } catch let failure as RelayInboxFailure {
            throw GitHubError(message: Self.serverMessage(failure))
        }
        try await authorizeServerSync()
    }

    /// Opens the relay's page where the user grants server sync on GitHub.
    /// Nothing is read until that grant exists: the relay answers 428.
    func authorizeServerSync() async throws {
        guard let access = serverAccess() else {
            throw GitHubError(message: "Authorize this Mac for live updates first.")
        }
        do {
            let url = try await RelayInboxClient(access: access).authorizationURL()
            openURL(url)
            server.authorizationStarted()
            schedule()
        } catch let failure as RelayInboxFailure {
            throw GitHubError(message: Self.serverMessage(failure))
        }
    }

    /// Deletes the relay's authorization and copy for all the user's Macs.
    func deleteServerSync() async throws {
        guard let access = serverAccess() else {
            throw GitHubError(message: "Authorize this Mac for live updates first.")
        }
        do {
            try await RelayInboxClient(access: access).delete()
            Log.actions.notice("GitHub: server sync deleted for all Macs")
            server.reset()
            applyServer()
        } catch let failure as RelayInboxFailure {
            throw GitHubError(message: Self.serverMessage(failure))
        }
    }

    private static func serverMessage(_ failure: RelayInboxFailure) -> String {
        switch failure {
        case .deviceExpired: GitHubServerHold.deviceExpired.message
        case .authorizationRequired: GitHubServerHold.authorizationRequired.message
        case .wrongAccount: GitHubServerHold.wrongAccount.message
        case .limited(let until?), .unavailable(let until?):
            "Server sync is not available right now. Try again after \(until.formatted(date: .omitted, time: .shortened))."
        case .limited(nil), .unavailable(nil): "Server sync is not available right now. Try again in a moment."
        case .invalidResponse: "The relay did not answer as expected: it may not offer server sync yet."
        }
    }

    private func apply(login: String?, pullRequests: [PullRequest]?, notifications answer: GitHubClient.NotificationsAnswer?) {
        if let pullRequests {
            let before = Set(self.pullRequests.map { "\($0.id)\($0.group)\($0.headSHA)" })
            let after = Set(pullRequests.map { "\($0.id)\($0.group)\($0.headSHA)" })
            if !self.pullRequests.isEmpty, before != after { activeUntil = .now.addingTimeInterval(Self.activeWindow) }
            if let login { self.login = login }
            self.pullRequests = pullRequests
            lastRefresh = .now
            Log.trace("GitHub: \(GitHubInbox.summary(pullRequests)), \(unreadNotifications.count) unread")
        }
        switch answer {
        case .changed(let list, let modified, let interval)?:
            notifications = list
            lastModified = modified
            pollInterval = max(interval, 30)
            nextNotifications = .now.addingTimeInterval(pollInterval)
        case .unchanged(let interval)?:
            pollInterval = max(interval, 30)
            nextNotifications = .now.addingTimeInterval(pollInterval)
        case nil:
            break
        }
        problem = nil
        onChange?()
    }

    private func failed(_ error: GitHubError) {
        problem = error.message
        busyUntil = error.retryAfter
        if error.signedOut { forgetToken() }
        Log.actions.notice("GitHub refresh failed: \(error.message, privacy: .private)")
        onChange?()
    }

    /// One timer, to the next refresh. With no relay, only the strip polls,
    /// as before. While the stream is up this is the notification poll;
    /// pull requests come from the wake. While it is down, the strip or
    /// GitHub mode uses the inbox timer this method always used.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard isSignedIn else { return }
        let connected = relay.isConnected
        if serverSync {
            guard keepsFresh || showsGitHub, let next = server.nextRead(connected: connected) else { return }
            let timer = Timer(timeInterval: max(next.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.server.readDue(connected: self.relay.isConnected)
                    self.schedule()
                }
            }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            return
        }
        let notificationsOnly = RelayPlan.suspendsInboxPoll(configured: relayIsConfigured, connected: connected)
        // No relay: only the strip polls, as before. With one, GitHub mode
        // also polls while the stream is down.
        guard keepsFresh || (showsGitHub && relayIsConfigured && !connected) else { return }
        var wait = pullRequests.contains { $0.group == .testing } || activeUntil > .now ? Self.activeSpacing : Self.idleSpacing
        wait = min(wait, max(nextNotifications.timeIntervalSinceNow, Self.minimumSpacing))
        if notificationsOnly {
            if let busyUntil, busyUntil > .now {
                wait = busyUntil.timeIntervalSinceNow
            } else {
                wait = max(nextNotifications.timeIntervalSinceNow, Self.minimumSpacing)
            }
        } else if let busyUntil, busyUntil > .now {
            wait = max(wait, busyUntil.timeIntervalSinceNow)
        }
        let retryInbox = notificationsOnly && busyUntil != nil
        let timer = Timer(timeInterval: max(wait, Self.minimumSpacing), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if retryInbox { self?.refresh(force: true) }
                else if notificationsOnly { self?.refresh(inbox: false) }
                else { self?.refresh() }
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var relayIsConfigured: Bool {
        resolvedRelayOrigin.flatMap { relayDevice.configuration(origin: $0.absoluteString) } != nil
    }

    private var resolvedRelayOrigin: URL? {
        let environment = (ProcessInfo.processInfo.environment["RELAY_PUBLIC_URL"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RelayAddress.origin(environment.isEmpty ? relayPublicURL : environment)
    }

    private func noteRelay() {
        // The relay's stream woke for its own copy: one read, folded.
        if serverSync { return server.readInbox() }
        if relayCoalescer.push(inFlight: refreshing != nil) {
            refresh(force: true)
            if refreshing == nil { _ = relayCoalescer.finished() }
        }
    }

    private func syncRelay() {
        let visible = keepsFresh || showsGitHub
        if (visible || showsSettings) && isSignedIn, let origin = resolvedRelayOrigin { relayDevice.activate(origin: origin.absoluteString) }
        else { relayDevice.suspend() }
        guard isSignedIn, RelayPlan.holdsStream(configured: relayIsConfigured, interfaceVisible: visible),
              let origin = resolvedRelayOrigin, let config = relayDevice.configuration(origin: origin.absoluteString) else {
            relayEndpoint = nil
            relay.stop()
            return
        }
        let endpoint = origin.absoluteString
        if relayEndpoint == endpoint, relayEndpointInbox == serverSync, relay.isRunning { return }
        relayEndpoint = endpoint
        relayEndpointInbox = serverSync
        relay.start(origin: origin, token: config.token, inbox: serverSync)
    }

    /// Drop a stale socket (sleep, network back) and open it again.
    private func reconnectRelay() {
        relayEndpoint = nil
        syncRelay()
    }

    /// Stores a token printed by `relay mint`. The GitHub token is a
    /// different Keychain item and is not accepted here.
    func saveRelayToken(_ raw: String) throws {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RelayToken.accepts(token) else {
            throw GitHubError(message: "That is not a relay stream token.")
        }
        try Keychain.save(token, account: relayAccount)
        relayToken = token
        hasRelayToken = true
        relayProblem = nil
        relayEndpoint = nil
        syncRelay()
    }

    /// Returns the token removed, kept in memory only while ⌘Z can save it
    /// again (`UndoableDeletes.relayToken`); never logged.
    @discardableResult
    func clearRelayToken() -> String? {
        let removed = relayToken
        Keychain.delete(account: relayAccount)
        relayToken = nil
        hasRelayToken = false
        relayProblem = nil
        relayEndpoint = nil
        syncRelay()
        schedule()
        return removed
    }

    /// Fresh for an agent: read again unless read in the last 15 s.
    func refreshed() async {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < Self.minimumSpacing { return }
        refresh(force: true)
        if serverSync { await server.settled() } else { await refreshing?.value }
    }

    // MARK: Acting

    func merge(_ pullRequest: PullRequest) async throws {
        guard let token else { throw GitHubError(message: "Sign in to GitHub in skil.li's Settings first.") }
        try await client.merge(pullRequest, token: token)
        Log.actions.notice("GitHub: merged \(pullRequest.repositoryFullName, privacy: .private)#\(pullRequest.number)")
        readAfterWrite()
    }

    func updateBranch(_ pullRequest: PullRequest) async throws {
        guard let token else { throw GitHubError(message: "Sign in to GitHub in skil.li's Settings first.") }
        try await client.updateBranch(pullRequest, token: token)
        readAfterWrite()
    }

    /// After a native write: the relay rereads GitHub (its copy is for all
    /// the user's Macs), else this Mac does.
    private func readAfterWrite() {
        if serverSync { server.readInbox(refresh: true) } else { refresh(force: true) }
    }

    func markRead(_ notification: GitHubNotification) async throws {
        guard let token else { throw GitHubError(message: "Sign in to GitHub in skil.li's Settings first.") }
        try await client.markRead(notification.id, token: token)
        if serverSync { return server.markedRead(notification.id) }
        notifications = notifications.map { $0.id == notification.id ? GitHubNotification(
            id: $0.id, reason: $0.reason, type: $0.type, title: $0.title, repository: $0.repository, updatedAt: $0.updatedAt, unread: false, url: $0.url) : $0 }
        onChange?()
    }

    func open(_ url: URL) {
        openURL(url)
    }

    // MARK: Signing in and out

    /// Gets a code from GitHub, copies it, opens github.com/login/device;
    /// signed in once the user has typed it there.
    func signIn() {
        signingIn?.cancel()
        signInProblem = nil
        let clientID = clientID()
        guard !clientID.isEmpty else {
            signInProblem = "This build of skil.li has no GitHub app to sign in with."
            return
        }
        let requestID = UUID()
        signInRequestID = requestID
        signingIn = Task { [client] in
            do {
                let code = try await client.startSignIn(clientID: clientID)
                guard signInRequestID == requestID, !Task.isCancelled else { return }
                signInCode = code
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                openURL(code.verificationURL)
                let token = try await client.waitForToken(code, clientID: clientID)
                guard signInRequestID == requestID, !Task.isCancelled else { return }
                try Keychain.save(token, account: keychainAccount)
                clearAccountData()
                self.token = token
                signInCode = nil
                Log.actions.notice("GitHub: signed in")
                refresh(force: true)
                syncRelay()
            } catch is CancellationError {
                guard signInRequestID == requestID else { return }
                signInCode = nil
            } catch {
                guard signInRequestID == requestID else { return }
                signInCode = nil
                signInProblem = error.localizedDescription
            }
            if signInRequestID == requestID { signingIn = nil; signInRequestID = nil }
        }
    }

    func cancelSignIn() {
        signInRequestID = nil
        signingIn?.cancel()
        signingIn = nil
        signInCode = nil
    }

    func signOut() {
        cancelSignIn()
        forgetToken()
        onChange?()
    }

    private func forgetToken() {
        Keychain.delete(account: keychainAccount)
        token = nil
        clearAccountData()
        syncRelay()
        schedule()
    }

    private func clearAccountData() {
        clearReadData()
        login = nil
    }

    /// What was read, from GitHub or the relay; any answer on its way is
    /// dropped.
    private func clearReadData() {
        accountGeneration = UUID()
        refreshing?.cancel()
        refreshing = nil
        busyUntil = nil
        lastAttempt = .distantPast
        nextNotifications = .distantPast
        pullRequests = []
        notifications = []
        notificationsComplete = true
        lastModified = nil
        lastRefresh = nil
        problem = nil
        serverHold = nil
        server.reset()
    }

    /// Self-test hook: a token as if the user had signed in.
    func signInForTest(token: String) throws {
        try Keychain.save(token, account: keychainAccount)
        clearAccountData()
        self.token = token
    }
}
