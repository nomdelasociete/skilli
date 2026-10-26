import Foundation

// Server sync: the relay reads the user's pull requests and notifications on
// GitHub with its own authorization (granted in the browser, never this
// Mac's GitHub token) and keeps one copy for all their Macs. skil.li reads
// that copy here; it classifies pull requests itself, as it does with
// GitHub's own answer. Writes (merge, update a branch, mark read) stay
// native. A relay that cannot answer is said, never replaced by a GitHub
// read.

/// This Mac's way to the server inbox, once its relay access and GitHub
/// identity are verified (`RelayDeviceSession.inboxAccess`).
public struct RelayInboxAccess: Sendable {
    public let authority: URL
    public let browser: URL
    public let token: String
    /// The numeric GitHub id the snapshots must be for.
    public let subject: String
    let send: RelayDeviceAPI.Send
}

/// Why the relay gave no inbox.
public enum RelayInboxFailure: Error, Equatable, Sendable {
    /// 401: this Mac's relay access expired or was refused; it renews.
    case deviceExpired
    /// 428: server sync is not authorized (or was deleted): the browser again.
    case authorizationRequired
    /// 429: too many requests from this account. `until`: the relay's
    /// `Retry-After`; nil without one (the caller's backoff decides).
    case limited(until: Date?)
    /// 503, the network, or GitHub's limits behind the relay.
    case unavailable(until: Date?)
    /// Malformed, incomplete or from an older relay.
    case invalidResponse
    /// For another GitHub account than this Mac's.
    case wrongAccount
}

public struct RelayInboxSnapshot: Sendable, Equatable {
    public let subject: String
    public let login: String
    public let updatedAt: Date
    public let revision: String
    public let pullRequests: [PullRequest]
}

public struct RelayNotificationsSnapshot: Sendable, Equatable {
    public let subject: String
    public let updatedAt: Date
    public let notifications: [GitHubNotification]
    /// False when GitHub had more unread threads than the relay keeps.
    public let complete: Bool
    /// When the relay will next ask GitHub (its `X-Poll-Interval`).
    public let pollInterval: TimeInterval
}

public enum RelayInbox {
    /// The relay's own cap on a snapshot.
    static let maximumBody = 8 << 20

    /// `Retry-After` in seconds or as an HTTP date.
    static func retryAfter(_ value: String?, now: Date = .now) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }

    /// The pull requests in the relay's snapshot, classified here. Every
    /// field the classification reads must be there: an older relay that
    /// does not send `isInMergeQueue` would otherwise show a queued pull
    /// request as ready.
    static func pullRequests(_ data: Data, subject: String, now: Date) throws -> RelayInboxSnapshot {
        guard data.count <= maximumBody, let wire = try? GitHubInbox.decoder.decode(WireInbox.self, from: data),
              let required = try? JSONDecoder().decode(WireRequired.self, from: data) else { throw RelayInboxFailure.invalidResponse }
        let updated = Date(timeIntervalSince1970: wire.updatedAt)
        guard wire.schema == 1, !wire.login.isEmpty, !wire.revision.isEmpty,
              updated <= now.addingTimeInterval(60), updated >= now.addingTimeInterval(-300) else { throw RelayInboxFailure.invalidResponse }
        guard wire.subject == subject else { throw RelayInboxFailure.wrongAccount }
        let nodes = wire.data.s0.nodes
        guard wire.data.s0.issueCount == nodes.count, required.data.s0.nodes.count == nodes.count,
              required.data.s0.nodes.allSatisfy(\.isComplete) else { throw RelayInboxFailure.invalidResponse }
        let pullRequests = nodes.compactMap { GitHubInbox.pullRequest($0, login: wire.login) }
        return RelayInboxSnapshot(subject: wire.subject, login: wire.login, updatedAt: updated, revision: wire.revision,
                                  pullRequests: GitHubInbox.sorted(pullRequests))
    }

    static func notifications(_ data: Data, subject: String, now: Date) throws -> RelayNotificationsSnapshot {
        guard data.count <= maximumBody, let wire = try? GitHubInbox.decoder.decode(WireNotifications.self, from: data)
        else { throw RelayInboxFailure.invalidResponse }
        let updated = Date(timeIntervalSince1970: wire.updatedAt)
        // Served from the relay's copy for up to GitHub's poll interval.
        guard wire.schema == 1, !wire.revision.isEmpty, (5...3600).contains(wire.pollInterval),
              updated <= now.addingTimeInterval(60), updated >= now.addingTimeInterval(-3660) else { throw RelayInboxFailure.invalidResponse }
        guard wire.subject == subject else { throw RelayInboxFailure.wrongAccount }
        return RelayNotificationsSnapshot(subject: wire.subject, updatedAt: updated, notifications: GitHubNotifications.notifications(wire.threads),
                                          complete: wire.complete, pollInterval: wire.pollInterval)
    }

    private struct WireInbox: Decodable {
        let schema: Int
        let subject: String
        let login: String
        let updatedAt: TimeInterval
        let revision: String
        let data: WireData

        struct WireData: Decodable { let s0: WireSearch }
        struct WireSearch: Decodable {
            let issueCount: Int
            let nodes: [GraphQLPullRequest]
        }
    }

    /// What `GraphQLPullRequest` reads as optional and the relay must send.
    private struct WireRequired: Decodable {
        let data: WireData
        struct WireData: Decodable { let s0: WireSearch }
        struct WireSearch: Decodable { let nodes: [Node] }
        struct Node: Decodable {
            let databaseId: Int
            let createdAt: String
            let isInMergeQueue: Bool
            let viewerCanUpdateBranch: Bool
            let commits: Commits?

            /// Every check listed (the relay pages them) and every commit
            /// status named.
            var isComplete: Bool {
                guard let contexts = commits?.nodes.compactMap({ $0?.commit?.statusCheckRollup?.contexts }).last else { return true }
                return contexts.totalCount == contexts.nodes.count
                    && contexts.nodes.allSatisfy { $0.__typename != "StatusContext" || $0.context?.isEmpty == false }
            }
        }
        struct Commits: Decodable { let nodes: [CommitNode?] }
        struct CommitNode: Decodable { let commit: Commit? }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let contexts: Contexts? }
        struct Contexts: Decodable {
            let totalCount: Int
            let nodes: [Context]
        }
        struct Context: Decodable {
            let __typename: String
            let context: String?
        }
    }

    private struct WireNotifications: Decodable {
        let schema: Int
        let subject: String
        let updatedAt: TimeInterval
        let revision: String
        let complete: Bool
        let pollInterval: TimeInterval
        let threads: [GitHubNotifications.Thread]
    }
}

/// The relay's inbox endpoints, on its authority, with this Mac's relay
/// access token: never the GitHub token, never another host, no redirects.
public struct RelayInboxClient: Sendable {
    public let access: RelayInboxAccess
    var now: @Sendable () -> Date = { Date() }

    public init(access: RelayInboxAccess) { self.access = access }

    /// `refresh`: POST, the relay rereads GitHub (spaced, limited); else
    /// its copy, reread by the relay at most once a minute.
    public func inbox(refresh: Bool = false) async throws -> RelayInboxSnapshot {
        let reply = try await call("inbox", method: refresh ? "POST" : "GET")
        return try RelayInbox.pullRequests(reply.data, subject: access.subject, now: now())
    }

    public func notifications(refresh: Bool = false) async throws -> RelayNotificationsSnapshot {
        let reply = try await call("inbox/notifications", method: refresh ? "POST" : "GET")
        return try RelayInbox.notifications(reply.data, subject: access.subject, now: now())
    }

    /// The page where the user grants server sync on GitHub: on the relay's
    /// browser origin only.
    public func authorizationURL() async throws -> URL {
        let reply = try await call("inbox/authorization", method: "POST")
        struct Answer: Decodable { let verification_uri: URL }
        guard let url = try? JSONDecoder().decode(Answer.self, from: reply.data).verification_uri,
              url.scheme == access.browser.scheme, url.host == access.browser.host, url.port == access.browser.port,
              url.path == "/inbox/authorize", url.user == nil, url.password == nil, url.fragment == nil
        else { throw RelayInboxFailure.invalidResponse }
        return url
    }

    /// Deletes the relay's authorization and copy for all the user's Macs.
    public func delete() async throws {
        _ = try await call("inbox", method: "DELETE", expect: 204)
    }

    private func call(_ path: String, method: String, expect: Int = 200) async throws -> RelayHTTPReply {
        var request = URLRequest(url: access.authority.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(access.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let reply: RelayHTTPReply
        do {
            reply = try await access.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RelayInboxFailure.unavailable(until: nil)
        }
        try Task.checkCancellation()
        let until = reply.retryAfter.map { now().addingTimeInterval(max(5, $0)) }
        switch reply.status {
        case expect: return reply
        case 401: throw RelayInboxFailure.deviceExpired
        case 428: throw RelayInboxFailure.authorizationRequired
        case 429: throw RelayInboxFailure.limited(until: until)
        case 500...599: throw RelayInboxFailure.unavailable(until: until)
        default: throw RelayInboxFailure.invalidResponse
        }
    }
}
