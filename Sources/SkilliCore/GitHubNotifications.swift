import Foundation

/// One of the user's GitHub notifications (their inbox on github.com):
/// review requests, mentions, comments, CI runs, state changes.
public struct GitHubNotification: Identifiable, Hashable, Sendable {
    /// The thread's id, what marking it read takes.
    public let id: String
    /// "review_requested", "mention", "ci_activity"…
    public let reason: String
    /// "PullRequest", "Issue", "CheckSuite", "Release"…
    public let type: String
    public let title: String
    /// "nomdelasociete/skilli"
    public let repository: String
    public let updatedAt: Date
    public let unread: Bool
    /// Its page on github.com.
    public let url: URL

    public init(id: String, reason: String, type: String, title: String, repository: String, updatedAt: Date, unread: Bool, url: URL) {
        self.id = id
        self.reason = reason
        self.type = type
        self.title = title
        self.repository = repository
        self.updatedAt = updatedAt
        self.unread = unread
        self.url = url
    }

    /// "Review requested", "Mentioned", "CI"…
    public var reasonTitle: String { GitHubNotifications.reasonTitle(reason) }

    /// Someone asks the user for something: a review, a mention, an
    /// assignment. Not the activity on their own threads or what they watch
    /// (2026-10-28: 35 of 334 unread), which skil.li neither counts nor lists.
    /// GitHub's reason for the thread, as its inbox's own filters
    /// (`reason:mention`…): a thread the user was mentioned in can keep
    /// "mention" for a later comment.
    public var isForYou: Bool { GitHubNotifications.forYou.contains(reason) }
}

/// One page of GitHub's `/notifications`, as the client fetched it.
public struct GitHubNotificationsPage: Sendable {
    public let status: Int
    public let data: Data
    public let lastModified: String?
    public let pollInterval: TimeInterval?
    /// GitHub's `Link` header names a next page.
    public let hasNext: Bool

    public init(status: Int, data: Data, lastModified: String?, pollInterval: TimeInterval?, hasNext: Bool) {
        self.status = status
        self.data = data
        self.lastModified = lastModified
        self.pollInterval = pollInterval
        self.hasNext = hasNext
    }
}

/// What a read of the notifications found.
public enum GitHubNotificationsRead: Sendable, Equatable {
    case unchanged(pollInterval: TimeInterval)
    /// `complete`: false when GitHub had more unread than `maxPages` pages.
    case changed([GitHubNotification], complete: Bool, lastModified: String?, pollInterval: TimeInterval)
}

public enum GitHubNotifications {
    /// GitHub's unread notifications, every page. Only the first request is
    /// conditional: unchanged, GitHub answers 304 and it costs nothing. A
    /// 200 to it lists only the threads changed since then, never the whole
    /// inbox (2026-10-27: 2 shown of 330), so a full read follows.
    public static func read(since: String?, maxPages: Int = 10,
                            page: @Sendable (_ number: Int, _ since: String?) async throws -> GitHubNotificationsPage) async throws -> GitHubNotificationsRead {
        var threads: [String: GitHubNotification] = [:]
        var lastModified: String?
        var pollInterval: TimeInterval = 60
        for number in 1...max(1, maxPages) {
            let answer = try await page(number, number == 1 ? since : nil)
            if number == 1 {
                pollInterval = answer.pollInterval ?? 60
                lastModified = answer.lastModified
                if since != nil {
                    if answer.status == 304 { return .unchanged(pollInterval: pollInterval) }
                    return try await read(since: nil, maxPages: maxPages, page: page)
                }
            }
            for notification in try parse(answer.data) { threads[notification.id] = notification }
            // GitHub's Link header decides, not the page's length.
            if !answer.hasNext {
                return .changed(sortedNewestFirst(threads), complete: true, lastModified: lastModified, pollInterval: pollInterval)
            }
        }
        return .changed(sortedNewestFirst(threads), complete: false, lastModified: lastModified, pollInterval: pollInterval)
    }

    private static func sortedNewestFirst(_ threads: [String: GitHubNotification]) -> [GitHubNotification] {
        threads.values.sorted { $0.updatedAt == $1.updatedAt ? $0.id > $1.id : $0.updatedAt > $1.updatedAt }
    }

    /// GitHub's notifications, newest first; those it cannot place are left
    /// out.
    public static func parse(_ data: Data) throws -> [GitHubNotification] {
        notifications(try GitHubInbox.decoder.decode([Thread].self, from: data))
    }

    /// The same threads, from the relay's copy (`RelayInbox`).
    static func notifications(_ threads: [Thread]) -> [GitHubNotification] {
        threads.compactMap { thread in
            guard let updated = GitHubInbox.date(thread.updatedAt) else { return nil }
            return GitHubNotification(id: thread.id, reason: thread.reason, type: thread.subject.type, title: thread.subject.title,
                                      repository: thread.repository.fullName, updatedAt: updated, unread: thread.unread,
                                      url: webURL(subject: thread.subject.url, type: thread.subject.type, repository: thread.repository.fullName))
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The API's address of the subject turned into its page:
    /// `api.github.com/repos/o/r/pulls/12` → `github.com/o/r/pull/12`;
    /// without one (a CI run, a discussion), the repository's page for its
    /// kind, else the notifications page.
    public static func webURL(subject: String?, type: String, repository: String) -> URL {
        let base = "https://github.com/"
        if let subject, let range = subject.range(of: "/repos/") {
            var path = String(subject[range.upperBound...])
            for (api, web) in [("/pulls/", "/pull/"), ("/commits/", "/commit/"), ("/releases/", "/releases/tag/")] {
                path = path.replacingOccurrences(of: api, with: web)
            }
            // A release's API address ends with its id, not its tag: the
            // releases list instead.
            if type == "Release", let tag = path.range(of: "/releases/tag/") { path = String(path[..<tag.lowerBound]) + "/releases" }
            if let url = URL(string: base + path) { return url }
        }
        let page = switch type {
        case "CheckSuite", "WorkflowRun": "/actions"
        case "Discussion": "/discussions"
        default: ""
        }
        return URL(string: base + repository + page) ?? URL(string: base + "notifications")!
    }

    /// The reasons that ask the user for something (`isForYou`).
    static let forYou: Set<String> = ["review_requested", "approval_requested", "mention", "team_mention", "assign", "invitation"]

    public static func reasonTitle(_ reason: String) -> String {
        switch reason {
        case "review_requested": "Review requested"
        case "mention", "team_mention": "Mentioned"
        case "author": "Your thread"
        case "comment": "Comment"
        case "assign": "Assigned"
        case "ci_activity": "CI"
        case "state_change": "State changed"
        case "subscribed", "manual": "Watching"
        case "security_alert": "Security alert"
        case "approval_requested": "Approval requested"
        case "invitation": "Invitation"
        default: reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    struct Thread: Decodable {
        let id: String
        let reason: String
        let unread: Bool
        let updatedAt: String
        let subject: Subject
        let repository: Repository

        private enum CodingKeys: String, CodingKey {
            case id, reason, unread, subject, repository
            case updatedAt = "updated_at"
        }
    }

    struct Subject: Decodable {
        let title: String
        let url: String?
        let type: String
    }

    struct Repository: Decodable {
        let fullName: String

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }
}
