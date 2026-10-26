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
}

public enum GitHubNotifications {
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
