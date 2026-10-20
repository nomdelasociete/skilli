import Foundation

// The user's GitHub pull requests in four groups, from one GraphQL request.
// Where each stands is GitHub's own merge box (`mergeStateStatus`: what
// github.com shows above the merge button), the review decision and the
// viewer's rights; the checks only name what runs or failed. Ready means
// the user can merge it now, nothing less.

/// Where a pull request stands, in the order shown: ready first.
public enum PullRequestGroup: String, CaseIterable, Sendable {
    case ready
    case blocked
    case waiting
    case testing

    public var title: String {
        switch self {
        case .ready: "Ready"
        case .blocked: "Blocked"
        case .waiting: "Waiting"
        case .testing: "Testing"
        }
    }

    public var symbol: String {
        switch self {
        case .ready: "checkmark"
        case .blocked: "exclamationmark"
        case .waiting: "clock"
        case .testing: "arrow.triangle.2.circlepath"
        }
    }
}

public enum PullRequestMergeMethod: String, Sendable {
    case merge
    case squash
    case rebase

    public var title: String {
        switch self {
        case .merge: "Merge"
        case .squash: "Squash and Merge"
        case .rebase: "Rebase and Merge"
        }
    }

    static func githubDefault(_ value: String?) -> PullRequestMergeMethod? {
        switch value?.uppercased() {
        case "MERGE": .merge
        case "SQUASH": .squash
        case "REBASE": .rebase
        default: nil
        }
    }
}

/// One pull request as skil.li shows it: in the launcher, under the search
/// field and to agents.
public struct PullRequest: Identifiable, Hashable, Sendable {
    public let id: Int
    /// "skilli"
    public let repository: String
    /// "nomdelasociete/skilli"
    public let repositoryFullName: String
    public let number: Int
    public let title: String
    public let group: PullRequestGroup
    /// "ci/woodpecker/pr/build failed", "Approved, ready to merge".
    public let reason: String
    /// "Your turn", "Checks running", "Ready to merge".
    public let statusLabel: String
    public let needsUserAction: Bool
    public let isAuthor: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let url: URL
    public let headSHA: String
    /// The repository's default for the user; nil where they may not merge
    /// (no write access): merging is not offered.
    public let defaultMergeMethod: PullRequestMergeMethod?
    /// Behind its base branch and the viewer may update it: "Update
    /// Branch" is offered.
    public let canUpdateBranch: Bool

    public init(id: Int, repository: String, repositoryFullName: String, number: Int, title: String, group: PullRequestGroup,
                reason: String, statusLabel: String, needsUserAction: Bool, isAuthor: Bool, createdAt: Date, updatedAt: Date, url: URL,
                headSHA: String, defaultMergeMethod: PullRequestMergeMethod?, canUpdateBranch: Bool) {
        self.id = id
        self.repository = repository
        self.repositoryFullName = repositoryFullName
        self.number = number
        self.title = title
        self.group = group
        self.reason = reason
        self.statusLabel = statusLabel
        self.needsUserAction = needsUserAction
        self.isAuthor = isAuthor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
        self.headSHA = headSHA
        self.defaultMergeMethod = defaultMergeMethod
        self.canUpdateBranch = canUpdateBranch
    }

    /// Ready (GitHub says it merges now) and the viewer may: merging is
    /// offered.
    public var canMerge: Bool { group == .ready && defaultMergeMethod != nil }
}

public enum GitHubInbox {
    /// The inbox in one request: the user's open pull requests and those
    /// waiting for their review, with what the classification needs.
    public static let query = """
        query Inbox($reviewRequested: String!) {
          viewer {
            login
            pullRequests(first: 50, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
              nodes { ...PR }
            }
          }
          search(query: $reviewRequested, type: ISSUE, first: 50) {
            nodes { ... on PullRequest { ...PR } }
          }
        }
        fragment PR on PullRequest {
          databaseId
          number
          title
          url
          state
          isDraft
          createdAt
          updatedAt
          author { login }
          headRefOid
          repository { nameWithOwner name isArchived viewerDefaultMergeMethod viewerPermission }
          reviewDecision
          mergeStateStatus
          mergeable
          isInMergeQueue
          viewerCanUpdateBranch
          viewerCanMergeAsAdmin
          reviewRequests(first: 20) { nodes { requestedReviewer { __typename ... on User { login } } } }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  state
                  contexts(first: 50) {
                    nodes {
                      __typename
                      ... on CheckRun { name status conclusion }
                      ... on StatusContext { context state }
                    }
                  }
                }
              }
            }
          }
        }
        """

    /// The search for pull requests waiting for the user's review.
    public static let reviewRequestedSearch = "is:pr is:open archived:false review-requested:@me -draft:true"

    public struct Failure: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// The pull requests in GitHub's answer to `query`, each once, sorted
    /// (`sorted`); throws GitHub's error message when it sent one.
    public static func pullRequests(fromResponse data: Data) throws -> (login: String, pullRequests: [PullRequest]) {
        let response = try decoder.decode(GraphQLResponse.self, from: data)
        if let error = response.errors?.first {
            throw Failure(message: error.message)
        }
        guard let viewer = response.data?.viewer else { throw Failure(message: "GitHub sent no pull requests.") }
        let nodes = (viewer.pullRequests?.nodes ?? []).compactMap { $0 } + (response.data?.search?.nodes ?? []).compactMap { $0 }
        var seen = Set<String>()
        let unique = nodes.filter { node in
            guard let repository = node.repository, node.number > 0 else { return false }
            return seen.insert("\(repository.nameWithOwner)#\(node.number)").inserted
        }
        let pullRequests = unique.compactMap { pullRequest($0, login: viewer.login) }
        return (viewer.login, sorted(pullRequests))
    }

    /// Ready, blocked, waiting, testing; the oldest first within each.
    public static func sorted(_ pullRequests: [PullRequest]) -> [PullRequest] {
        let order = Dictionary(uniqueKeysWithValues: PullRequestGroup.allCases.enumerated().map { ($1, $0) })
        return pullRequests.sorted { lhs, rhs in
            lhs.group == rhs.group ? lhs.createdAt < rhs.createdAt : order[lhs.group, default: 0] < order[rhs.group, default: 0]
        }
    }

    /// How many in each group.
    public static func counts(_ pullRequests: [PullRequest]) -> [PullRequestGroup: Int] {
        Dictionary(grouping: pullRequests, by: \.group).mapValues(\.count)
    }

    /// "2 ready · 1 blocked", the groups with pull requests only; empty when
    /// there are none.
    public static func summary(_ pullRequests: [PullRequest]) -> String {
        let counts = counts(pullRequests)
        return PullRequestGroup.allCases.compactMap { group in
            counts[group].map { "\($0) \(group.title.lowercased())" }
        }.joined(separator: " · ")
    }

    static func pullRequest(_ node: GraphQLPullRequest, login: String) -> PullRequest? {
        guard node.state.uppercased() == "OPEN", let repository = node.repository, repository.isArchived != true,
              let url = URL(string: node.url) else { return nil }
        let author = node.author?.login ?? ""
        let rollup = node.commits?.nodes?.compactMap { $0?.commit?.statusCheckRollup }.last
        let contexts = rollup?.contexts?.nodes?.compactMap { $0 } ?? []
        let mayMerge = ["WRITE", "MAINTAIN", "ADMIN"].contains(repository.viewerPermission?.uppercased() ?? "") || node.viewerCanMergeAsAdmin == true
        let facts = PullRequestFacts(
            isDraft: node.isDraft ?? false, mergeStateStatus: node.mergeStateStatus, mergeable: node.mergeable,
            reviewDecision: node.reviewDecision, checks: rollup?.state,
            failingCheck: contexts.first(where: \.isFailing)?.label, runningCheck: contexts.first(where: \.isRunning)?.label,
            isAuthor: author == login,
            isRequestedReviewer: (node.reviewRequests?.nodes ?? []).contains { $0?.requestedReviewer?.login == login },
            viewerCanMerge: mayMerge, viewerCanUpdateBranch: node.viewerCanUpdateBranch ?? mayMerge, isInMergeQueue: node.isInMergeQueue ?? false)
        let classification = classify(facts)
        return PullRequest(
            id: node.databaseId ?? node.number, repository: repository.name, repositoryFullName: repository.nameWithOwner, number: node.number,
            title: node.title, group: classification.group, reason: classification.reason, statusLabel: classification.statusLabel,
            needsUserAction: classification.needsUserAction, isAuthor: facts.isAuthor, createdAt: node.createdAt ?? .distantPast,
            updatedAt: node.updatedAt ?? node.createdAt ?? .distantPast, url: url, headSHA: node.headRefOid ?? "",
            defaultMergeMethod: mayMerge ? PullRequestMergeMethod.githubDefault(repository.viewerDefaultMergeMethod) : nil,
            canUpdateBranch: classification.canUpdateBranch)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = date(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GitHub date: \(string)")
        }
        return decoder
    }()

    static func date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Where a pull request stands

    /// GitHub's merge box first: it already weighs branch protection,
    /// required checks, required reviews and conflicts. The review
    /// decision and the checks only say why it is blocked, and the
    /// viewer's rights whether "ready" is theirs to merge.
    static func classify(_ facts: PullRequestFacts) -> PullRequestClassification {
        let author = facts.isAuthor
        func authorsTurn(_ reason: String, _ label: String) -> PullRequestClassification {
            PullRequestClassification(group: .blocked, reason: reason, statusLabel: author ? "Your turn" : label, needsUserAction: author)
        }
        if facts.isDraft { return authorsTurn("Draft", "Draft") }
        if facts.isInMergeQueue {
            return PullRequestClassification(group: .testing, reason: "In the merge queue", statusLabel: "Merging", needsUserAction: false)
        }
        let state = facts.mergeStateStatus?.uppercased()
        if state == "DIRTY" || facts.mergeable?.uppercased() == "CONFLICTING" { return authorsTurn("Merge conflict", "Conflict") }
        let checksRunning = ["PENDING", "EXPECTED"].contains(facts.checks?.uppercased() ?? "")
        let checksFailed = ["FAILURE", "ERROR"].contains(facts.checks?.uppercased() ?? "")
        let running = PullRequestClassification(group: .testing, reason: facts.runningCheck.map { "\($0) running" } ?? "Checks running",
                                                statusLabel: "Checks running", needsUserAction: false)
        let failed = facts.failingCheck.map { "\($0) failed" } ?? "Checks failed"
        switch state {
        case "BEHIND":
            return PullRequestClassification(group: .blocked, reason: "Behind its base branch",
                                             statusLabel: facts.viewerCanUpdateBranch ? "Update branch" : "Behind",
                                             needsUserAction: author || facts.viewerCanUpdateBranch, canUpdateBranch: facts.viewerCanUpdateBranch)
        case "BLOCKED":
            if facts.reviewDecision?.uppercased() == "CHANGES_REQUESTED" { return authorsTurn("Changes requested", "Changes requested") }
            if checksFailed { return authorsTurn(failed, "Checks failed") }
            if checksRunning { return running }
            if facts.reviewDecision?.uppercased() == "REVIEW_REQUIRED" {
                return facts.isRequestedReviewer && !author
                    ? PullRequestClassification(group: .waiting, reason: "Review requested", statusLabel: "Your review", needsUserAction: true)
                    : PullRequestClassification(group: .waiting, reason: "Waiting for review", statusLabel: "Awaiting review", needsUserAction: false)
            }
            return authorsTurn("Blocked by a branch rule", "Blocked")
        case "UNSTABLE":
            // Mergeable, but a check that is not required did not pass:
            // never shown as ready.
            if checksRunning { return running }
            return authorsTurn("\(failed) (not required)", "Checks failed")
        case "CLEAN", "HAS_HOOKS":
            if facts.viewerCanMerge {
                let approved = facts.reviewDecision?.uppercased() == "APPROVED"
                return PullRequestClassification(group: .ready, reason: approved ? "Approved, ready to merge" : "Ready to merge",
                                                 statusLabel: "Ready to merge", needsUserAction: true)
            }
            // Someone else's repository: theirs to merge.
            return PullRequestClassification(group: .waiting, reason: "Ready, the maintainers merge it", statusLabel: "Maintainers' turn",
                                             needsUserAction: false)
        default:
            // UNKNOWN, or not computed yet: GitHub works it out.
            return PullRequestClassification(group: .testing, reason: "GitHub is checking", statusLabel: "Checking", needsUserAction: false)
        }
    }
}

// MARK: - The classification's inputs

/// What GitHub says of one pull request, for `GitHubInbox.classify`.
struct PullRequestFacts {
    var isDraft = false
    /// CLEAN, HAS_HOOKS, UNSTABLE, BLOCKED, BEHIND, DIRTY, UNKNOWN.
    var mergeStateStatus: String?
    /// MERGEABLE, CONFLICTING, UNKNOWN.
    var mergeable: String?
    /// APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or nil.
    var reviewDecision: String?
    /// The checks' rollup: SUCCESS, PENDING, EXPECTED, FAILURE, ERROR.
    var checks: String?
    /// "lint", "ci/woodpecker/pr/build": to say which one.
    var failingCheck: String?
    var runningCheck: String?
    var isAuthor = false
    var isRequestedReviewer = false
    /// Write access or more (or an admin's bypass).
    var viewerCanMerge = false
    var viewerCanUpdateBranch = false
    var isInMergeQueue = false
}

struct PullRequestClassification: Equatable {
    let group: PullRequestGroup
    let reason: String
    let statusLabel: String
    let needsUserAction: Bool
    let canUpdateBranch: Bool

    init(group: PullRequestGroup, reason: String, statusLabel: String, needsUserAction: Bool, canUpdateBranch: Bool = false) {
        self.group = group
        self.reason = reason
        self.statusLabel = statusLabel
        self.needsUserAction = needsUserAction
        self.canUpdateBranch = canUpdateBranch
    }
}

// MARK: - GitHub's GraphQL answer

struct GraphQLResponse: Decodable {
    let data: GraphQLInbox?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}

struct GraphQLInbox: Decodable {
    let viewer: GraphQLViewer?
    let search: GraphQLNodes<GraphQLPullRequest>?
}

struct GraphQLViewer: Decodable {
    let login: String
    let pullRequests: GraphQLNodes<GraphQLPullRequest>?
}

struct GraphQLNodes<Node: Decodable>: Decodable {
    let nodes: [Node?]?
}

struct GraphQLPullRequest: Decodable {
    let databaseId: Int?
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let author: GraphQLLogin?
    let headRefOid: String?
    let repository: GraphQLRepository?
    let reviewDecision: String?
    let mergeStateStatus: String?
    let mergeable: String?
    let isInMergeQueue: Bool?
    let viewerCanUpdateBranch: Bool?
    let viewerCanMergeAsAdmin: Bool?
    let reviewRequests: GraphQLNodes<GraphQLReviewRequest>?
    let commits: GraphQLNodes<GraphQLCommitNode>?

    /// Search results that are not pull requests come back empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        databaseId = try container.decodeIfPresent(Int.self, forKey: .databaseId)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        author = try container.decodeIfPresent(GraphQLLogin.self, forKey: .author)
        headRefOid = try container.decodeIfPresent(String.self, forKey: .headRefOid)
        repository = try container.decodeIfPresent(GraphQLRepository.self, forKey: .repository)
        reviewDecision = try container.decodeIfPresent(String.self, forKey: .reviewDecision)
        mergeStateStatus = try container.decodeIfPresent(String.self, forKey: .mergeStateStatus)
        mergeable = try container.decodeIfPresent(String.self, forKey: .mergeable)
        isInMergeQueue = try container.decodeIfPresent(Bool.self, forKey: .isInMergeQueue)
        viewerCanUpdateBranch = try container.decodeIfPresent(Bool.self, forKey: .viewerCanUpdateBranch)
        viewerCanMergeAsAdmin = try container.decodeIfPresent(Bool.self, forKey: .viewerCanMergeAsAdmin)
        reviewRequests = try container.decodeIfPresent(GraphQLNodes<GraphQLReviewRequest>.self, forKey: .reviewRequests)
        commits = try container.decodeIfPresent(GraphQLNodes<GraphQLCommitNode>.self, forKey: .commits)
    }

    private enum CodingKeys: String, CodingKey {
        case databaseId, number, title, url, state, isDraft, createdAt, updatedAt, author, headRefOid, repository, reviewDecision,
             mergeStateStatus, mergeable, isInMergeQueue, viewerCanUpdateBranch, viewerCanMergeAsAdmin, reviewRequests, commits
    }
}

struct GraphQLLogin: Decodable {
    let login: String
}

struct GraphQLRepository: Decodable {
    let nameWithOwner: String
    let name: String
    let isArchived: Bool?
    let viewerDefaultMergeMethod: String?
    /// READ, TRIAGE, WRITE, MAINTAIN, ADMIN.
    let viewerPermission: String?
}

struct GraphQLReviewRequest: Decodable {
    /// A user's login; teams have none.
    let requestedReviewer: GraphQLLoginOrTeam?
}

struct GraphQLLoginOrTeam: Decodable {
    let login: String?
}

struct GraphQLCommitNode: Decodable {
    let commit: GraphQLCommit?
}

struct GraphQLCommit: Decodable {
    let statusCheckRollup: GraphQLRollup?
}

struct GraphQLRollup: Decodable {
    let state: String?
    let contexts: GraphQLNodes<GraphQLContext>?
}

/// A check run (`name`, `status`, `conclusion`) or a commit status
/// (`context`, `state`: what Woodpecker and Vercel post).
struct GraphQLContext: Decodable {
    let typename: String
    let name: String?
    let status: String?
    let conclusion: String?
    let context: String?
    let state: String?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, status, conclusion, context, state
    }

    /// The check's name, or the status's context.
    var label: String? { name ?? context }

    var isRunning: Bool {
        if typename == "CheckRun" { return ["QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "PENDING"].contains(status?.uppercased() ?? "") }
        return ["PENDING", "EXPECTED"].contains(state?.uppercased() ?? "")
    }

    var isFailing: Bool {
        if typename == "CheckRun" {
            return status?.uppercased() == "COMPLETED"
                && ["ACTION_REQUIRED", "CANCELLED", "FAILURE", "STALE", "STARTUP_FAILURE", "TIMED_OUT"].contains(conclusion?.uppercased() ?? "")
        }
        return ["FAILURE", "ERROR"].contains(state?.uppercased() ?? "")
    }
}
