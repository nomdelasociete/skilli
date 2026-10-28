import Foundation

/// What keeps the relay's copy from showing, in the user's words. Never a
/// reason to read GitHub from this Mac instead.
public enum GitHubServerHold: Equatable, Sendable {
    /// No verified relay access on this Mac (not authorized, revoked, or
    /// its GitHub account not checked yet).
    case macNotReady
    /// Server sync was never authorized in the browser, or was deleted.
    case authorizationRequired
    /// This Mac's relay access is renewing.
    case deviceExpired
    case paused(until: Date)
    case wrongAccount

    public var message: String {
        switch self {
        case .macNotReady: "Server sync waits for this Mac's live updates authorization."
        case .authorizationRequired: "Server sync needs your authorization in the browser."
        case .deviceExpired: "This Mac's relay access is renewing."
        case .paused(let until): "The relay is paused until \(until.formatted(date: .omitted, time: .shortened)); the last copy stays."
        case .wrongAccount: "The relay answered for another GitHub account: nothing of it is shown."
        }
    }
}

/// Paces one kind of relay read: the relay's `Retry-After` when it gives
/// one, else a backoff from 30 s to 15 min that grows with each failure in
/// a row (a 503 without the header, the network). Never zero, so no loop.
public struct RelayReadPacer: Sendable, Equatable {
    public private(set) var notBefore = Date.distantPast
    public private(set) var failures = 0

    public init() {}

    public func allows(_ now: Date) -> Bool { now >= notBefore }

    public mutating func succeeded(next: Date) {
        failures = 0
        notBefore = next
    }

    /// When to ask again.
    @discardableResult
    public mutating func failed(_ failure: RelayInboxFailure, now: Date) -> Date {
        failures = min(failures + 1, 6)
        let backoff = now.addingTimeInterval(min(15 * 60, 30 * pow(2, Double(failures - 1))))
        notBefore = switch failure {
        case .limited(let until?), .unavailable(let until?): max(until, now.addingTimeInterval(5))
        case .limited(nil), .unavailable(nil): backoff
        // Nothing changes until the user authorizes; checked now and then
        // for another Mac's authorization, never with a new browser page.
        case .authorizationRequired: now.addingTimeInterval(5 * 60)
        case .deviceExpired: now.addingTimeInterval(30)
        case .invalidResponse, .wrongAccount: backoff
        }
        return notBefore
    }

    public mutating func reset() { self = RelayReadPacer() }

    mutating func wait(until date: Date) { notBefore = date }
}

/// The user's GitHub inbox read from the relay (server sync): one read of
/// each kind at a time, wakes during a read folded into one more, the
/// relay's pace and refusals kept, late answers (after sign-out, an account
/// change, turning it off) dropped. It has no way to GitHub: in server
/// sync, nothing else reads pull requests or notifications.
@MainActor
public final class GitHubServerInbox {
    public private(set) var pullRequests: [PullRequest]?
    public private(set) var login: String?
    public private(set) var notifications: [GitHubNotification]?
    public private(set) var notificationsComplete = true
    public private(set) var inboxHold: GitHubServerHold?
    public private(set) var notificationsHold: GitHubServerHold?
    public private(set) var lastInboxRead: Date?
    public private(set) var inbox = RelayReadPacer()
    public private(set) var notes = RelayReadPacer()

    /// The relay's copy changed or a hold did (the owner redraws).
    public var onChange: () -> Void = {}
    /// 401: the owner renews this Mac's relay access.
    public var onDeviceExpired: () -> Void = {}

    /// This Mac's way to the relay; nil until its access and GitHub
    /// identity are verified.
    public var client: () -> RelayInboxClient?
    private let now: () -> Date
    private var generation = 0
    private var inboxTask: Task<Void, Never>?
    private var notesTask: Task<Void, Never>?
    private var inboxAgain = false
    private var refreshAgain = false
    private var notesAgain = false
    /// After the browser was opened: 428 checked every 5 s for 10 min.
    private var awaitingAuthorizationUntil = Date.distantPast

    /// Between two reads of the relay's copy while the stream is up: the
    /// relay reconciles with GitHub at most once a minute, so asking more
    /// often adds relay calls, not freshness. While it is down, wakes are
    /// missed: twice as often.
    public static let connectedSpacing: TimeInterval = 60
    public static let disconnectedSpacing: TimeInterval = 30

    public init(client: @escaping () -> RelayInboxClient?, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    /// The first problem, inbox first.
    public var hold: GitHubServerHold? { inboxHold ?? notificationsHold }
    public var isReading: Bool { inboxTask != nil || notesTask != nil }

    // MARK: Reading

    /// The relay's copy of the pull requests. `refresh` asks the relay to
    /// read GitHub again (Read Now, after a merge). A read already running
    /// is followed by one more, never two.
    public func readInbox(refresh: Bool = false) {
        if inboxTask != nil {
            inboxAgain = true
            refreshAgain = refreshAgain || refresh
            return
        }
        guard refresh || inbox.allows(now()) || inboxHold == .macNotReady else { return }
        guard let client = client() else { return holdBoth(.macNotReady) }
        let generation = generation
        inboxTask = Task { [weak self] in
            let result: Result<RelayInboxSnapshot, RelayInboxFailure>
            do { result = .success(try await client.inbox(refresh: refresh)) }
            catch let failure as RelayInboxFailure { result = .failure(failure) }
            catch { return }
            self?.finishInbox(result, generation: generation, subject: client.access.subject)
        }
    }

    public func readNotifications(refresh: Bool = false) {
        if notesTask != nil {
            notesAgain = notesAgain || refresh
            return
        }
        guard refresh || notes.allows(now()) || notificationsHold == .macNotReady else { return }
        guard let client = client() else { return holdBoth(.macNotReady) }
        let generation = generation
        notesTask = Task { [weak self] in
            let result: Result<RelayNotificationsSnapshot, RelayInboxFailure>
            do { result = .success(try await client.notifications(refresh: refresh)) }
            catch let failure as RelayInboxFailure { result = .failure(failure) }
            catch { return }
            self?.finishNotifications(result, generation: generation, subject: client.access.subject)
        }
    }

    /// Waits for the reads running now (agents ask, then list).
    public func settled() async {
        while let task = inboxTask ?? notesTask { await task.value }
    }

    /// The browser page was opened: watch for the grant a little closer.
    public func authorizationStarted() {
        awaitingAuthorizationUntil = now().addingTimeInterval(10 * 60)
        if inboxHold == .authorizationRequired { inbox.reset(); notes.reset() }
    }

    /// The owner's timer fired: what is due, each at its own pace.
    public func readDue(connected: Bool) {
        let spacing = connected ? Self.connectedSpacing : Self.disconnectedSpacing
        if now() >= (lastInboxRead ?? .distantPast).addingTimeInterval(spacing) || inboxHold != nil { readInbox() }
        readNotifications()
    }

    /// When the owner's timer should read next; nil: nothing to wait for.
    public func nextRead(connected: Bool) -> Date? {
        let spacing = connected ? Self.connectedSpacing : Self.disconnectedSpacing
        var inboxAt = max(inbox.notBefore, (lastInboxRead ?? .distantPast).addingTimeInterval(spacing))
        if inboxHold == .authorizationRequired, now() < awaitingAuthorizationUntil {
            inboxAt = min(inboxAt, now().addingTimeInterval(5))
        }
        if inboxHold == .macNotReady { return nil }
        return max(now(), min(inboxAt, notes.notBefore))
    }

    /// Sign-out, another account, server sync turned off or deleted: what
    /// was read goes, and any answer still on its way is dropped.
    public func reset() {
        generation += 1
        inboxTask?.cancel()
        notesTask?.cancel()
        inboxTask = nil
        notesTask = nil
        inboxAgain = false
        refreshAgain = false
        notesAgain = false
        pullRequests = nil
        login = nil
        notifications = nil
        notificationsComplete = true
        inboxHold = nil
        notificationsHold = nil
        lastInboxRead = nil
        inbox.reset()
        notes.reset()
        awaitingAuthorizationUntil = .distantPast
    }

    /// A native write changed a notification: shown at once, then the
    /// relay is told so its copy (and the user's other Macs) follow.
    public func markedRead(_ id: String) {
        markedRead([id])
    }

    /// Several at once (Mark All as Read): one reread.
    public func markedRead(_ ids: Set<String>) {
        notifications = notifications?.map { ids.contains($0.id) ? GitHubNotification(
            id: $0.id, reason: $0.reason, type: $0.type, title: $0.title, repository: $0.repository,
            updatedAt: $0.updatedAt, unread: false, url: $0.url) : $0 }
        onChange()
        readNotifications(refresh: true)
    }

    // MARK: Answers

    private func finishInbox(_ result: Result<RelayInboxSnapshot, RelayInboxFailure>, generation: Int, subject: String) {
        guard generation == self.generation else { return }
        inboxTask = nil
        // The Mac may have changed account while the relay answered.
        if client()?.access.subject != subject { return holdBoth(.macNotReady) }
        switch result {
        case .success(let snapshot):
            pullRequests = snapshot.pullRequests
            login = snapshot.login
            lastInboxRead = now()
            inbox.succeeded(next: now())
            inboxHold = nil
            awaitingAuthorizationUntil = .distantPast
            if notificationsHold == .authorizationRequired { notes.reset(); readNotifications() }
        case .failure(let failure):
            inbox.failed(failure, now: now())
            if failure == .authorizationRequired, now() < awaitingAuthorizationUntil { inbox.wait(until: now().addingTimeInterval(5)) }
            fail(failure, inbox: true)
        }
        onChange()
        if inboxAgain {
            let refresh = refreshAgain
            inboxAgain = false
            refreshAgain = false
            readInbox(refresh: refresh)
        }
    }

    private func finishNotifications(_ result: Result<RelayNotificationsSnapshot, RelayInboxFailure>, generation: Int, subject: String) {
        guard generation == self.generation else { return }
        notesTask = nil
        if client()?.access.subject != subject { return holdBoth(.macNotReady) }
        switch result {
        case .success(let snapshot):
            notifications = snapshot.notifications
            notificationsComplete = snapshot.complete
            notes.succeeded(next: now().addingTimeInterval(snapshot.pollInterval))
            notificationsHold = nil
        case .failure(let failure):
            notes.failed(failure, now: now())
            fail(failure, inbox: false)
        }
        onChange()
        if notesAgain {
            notesAgain = false
            readNotifications(refresh: true)
        }
    }

    private func fail(_ failure: RelayInboxFailure, inbox: Bool) {
        let hold: GitHubServerHold = switch failure {
        case .deviceExpired: .deviceExpired
        case .authorizationRequired: .authorizationRequired
        case .wrongAccount: .wrongAccount
        case .limited, .unavailable, .invalidResponse: .paused(until: inbox ? self.inbox.notBefore : notes.notBefore)
        }
        // Without an authorization, or for another account, nothing read
        // under it stays on screen.
        if failure == .authorizationRequired || failure == .wrongAccount {
            if inbox { pullRequests = nil; login = nil } else { notifications = nil }
        }
        if inbox { inboxHold = hold } else { notificationsHold = hold }
        if failure == .deviceExpired { onDeviceExpired() }
    }

    private func holdBoth(_ hold: GitHubServerHold) {
        let changed = inboxHold != hold || notificationsHold != hold || pullRequests != nil || notifications != nil
        generation += 1
        inboxTask?.cancel()
        notesTask?.cancel()
        inboxTask = nil
        notesTask = nil
        // Reads asked for the dropped answers go with them.
        inboxAgain = false
        refreshAgain = false
        notesAgain = false
        pullRequests = nil
        login = nil
        notifications = nil
        inboxHold = hold
        notificationsHold = hold
        if changed { onChange() }
    }
}
