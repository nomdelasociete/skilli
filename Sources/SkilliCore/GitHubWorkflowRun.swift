import Foundation

/// A GitHub Actions workflow started from skil.li and followed
/// (docs/github-workflow-runs.md): what to start, and what GitHub says of
/// the run, its jobs and steps, read into what the menu bar item and the
/// end card show. Pure: the requests are `GitHubWorkflows`'.
public struct WorkflowDispatch: Equatable, Sendable {
    /// "owner/name".
    public let repository: String
    /// The workflow's file name ("release.yml") or its id.
    public let workflow: String
    /// The branch or tag; nil: the repository's default branch.
    public let ref: String?
    /// Its `workflow_dispatch` inputs, as GitHub takes them (text).
    public let inputs: [String: String]

    /// GitHub takes 25 inputs at most.
    public static let mostInputs = 25

    public struct Invalid: Error, Equatable, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public init(repository: String, workflow: String, ref: String? = nil, inputs: [String: String] = [:]) throws {
        let repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let workflow = workflow.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repository.wholeMatch(of: /[A-Za-z0-9\-]+\/[A-Za-z0-9._\-]+/) != nil, Self.isName(repository) else {
            throw Invalid(message: "“\(repository)” is not a repository: owner/name, as in nomdelasociete/skilli.")
        }
        guard workflow.wholeMatch(of: /[A-Za-z0-9._\-]+/) != nil, workflow != "..", workflow != "." else {
            throw Invalid(message: "“\(workflow)” is not a workflow: its file name in .github/workflows (release.yml) or its id.")
        }
        if let ref, !ref.isEmpty {
            guard ref.wholeMatch(of: /[A-Za-z0-9._\/\-]+/) != nil, !ref.contains(".."), !ref.hasPrefix("/"), !ref.hasSuffix("/") else {
                throw Invalid(message: "“\(ref)” is not a branch or a tag.")
            }
        }
        guard inputs.count <= Self.mostInputs else { throw Invalid(message: "GitHub takes \(Self.mostInputs) inputs at most.") }
        if let bad = inputs.keys.sorted().first(where: { $0.wholeMatch(of: /[A-Za-z0-9_\-]+/) == nil }) {
            throw Invalid(message: "“\(bad)” is not an input's name.")
        }
        self.repository = repository
        self.workflow = workflow
        self.ref = (ref?.isEmpty ?? true) ? nil : ref
        self.inputs = inputs
    }

    /// "owner/name" whose name is not `.` or `..`: a path GitHub's URLs
    /// could fold into another repository's.
    static func isName(_ repository: String) -> Bool {
        let name = repository.split(separator: "/").last ?? ""
        return name != "." && name != ".."
    }

    /// The inputs a tool is given, as one JSON object: text, true/false
    /// and numbers are kept as GitHub takes them (text).
    public static func inputs(fromJSON text: String) throws -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            throw Invalid(message: "inputs is a JSON object: {\"bump\":\"patch\",\"critical\":false}.")
        }
        var inputs: [String: String] = [:]
        for (name, value) in object {
            switch value {
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): inputs[name] = number.boolValue ? "true" : "false"
            case let number as NSNumber: inputs[name] = number.stringValue
            case let text as String: inputs[name] = text
            default: throw Invalid(message: "The input “\(name)” is text, true, false or a number.")
            }
        }
        return inputs
    }

    /// "release.yml on nomdelasociete/skilli main", as the card names it.
    public var said: String {
        "\(workflow) on \(repository)" + (ref.map { " \($0)" } ?? "")
    }

    /// "bump: patch · critical: false", in name order; "" without inputs.
    public var saidInputs: String {
        inputs.keys.sorted().map { "\($0): \(inputs[$0] ?? "")" }.joined(separator: " · ")
    }

    /// What the card asks before it starts, from the tool or a link: the
    /// workflow, its inputs, the approval its ↩ also gives.
    public var asked: String {
        let inputs = saidInputs.isEmpty ? "" : "\n" + saidInputs
        return "\(said)\(ref == nil ? ", its default branch" : "")\(inputs)\n"
            + "Its environment is approved too when you may approve it. What it publishes stays published."
    }

    /// The workflow's runs on GitHub, where to look when a run is not found.
    public var runsPage: URL {
        URL(string: "https://github.com/\(repository)/actions/workflows/\(workflow)")!
    }
}

/// A run's or a job's or a step's state, from GitHub's `status` and
/// `conclusion`.
public enum WorkflowState: String, Equatable, Sendable {
    case queued, waiting, running, succeeded, failed, cancelled, skipped

    public init(status: String?, conclusion: String?) {
        switch status {
        case "completed":
            switch conclusion {
            case "success", "neutral": self = .succeeded
            case "cancelled": self = .cancelled
            case "skipped": self = .skipped
            default: self = .failed
            }
        case "in_progress": self = .running
        case "waiting", "action_required": self = .waiting
        default: self = .queued
        }
    }

    public var isDone: Bool { [.succeeded, .failed, .cancelled, .skipped].contains(self) }

    /// The SF Symbol each state shows with in the menu.
    public var symbol: String {
        switch self {
        case .queued: "circle.dashed"
        case .waiting: "hand.raised"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        case .skipped: "minus.circle"
        }
    }
}

public struct WorkflowStep: Equatable, Sendable {
    public let number: Int
    public let name: String
    public let state: WorkflowState
    public let startedAt: Date?
    public let completedAt: Date?
}

public struct WorkflowJob: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let state: WorkflowState
    public let url: URL?
    public let steps: [WorkflowStep]
}

public struct WorkflowRun: Equatable, Sendable {
    public let id: Int
    public let repository: String
    /// What GitHub's list shows ("Release patch", the workflow's `run-name`).
    public let title: String
    public let number: Int
    public let state: WorkflowState
    public let url: URL
    public let createdAt: Date
    public let startedAt: Date?
    public let actor: String?
    public let event: String?

    /// The same run, its repository `repository` when GitHub's answer did
    /// not name one.
    public func named(_ repository: String) -> WorkflowRun {
        guard self.repository.isEmpty else { return self }
        return WorkflowRun(id: id, repository: repository, title: title, number: number, state: state, url: url,
                           createdAt: createdAt, startedAt: startedAt, actor: actor, event: event)
    }

    /// skil.li's name for a run, to read it again: its page on GitHub.
    public static func parse(link: String) -> (repository: String, id: Int)? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.wholeMatch(of: /https:\/\/github\.com\/([A-Za-z0-9\-]+\/[A-Za-z0-9._\-]+)\/actions\/runs\/([0-9]+)(\/.*)?/),
              let id = Int(match.output.2), WorkflowDispatch.isName(String(match.output.1)) else { return nil }
        return (String(match.output.1), id)
    }
}

/// A release of the repository: the one a run published.
public struct WorkflowRelease: Equatable, Sendable {
    public let tag: String
    public let name: String
    public let url: URL
    public let publishedAt: Date
}

/// GitHub's answers read.
public enum GitHubWorkflowAnswers {
    private static func dictionary(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    /// The dispatch's own answer, when GitHub gives the run's id.
    public static func dispatchedRunID(_ data: Data) -> Int? {
        dictionary(data)?["workflow_run_id"] as? Int
    }

    public static func run(_ data: Data) -> WorkflowRun? {
        dictionary(data).flatMap(run(from:))
    }

    static func run(from object: [String: Any]) -> WorkflowRun? {
        guard let id = object["id"] as? Int, let url = (object["html_url"] as? String).flatMap(URL.init(string:)),
              let created = date(object["created_at"]) else { return nil }
        let repository = (object["repository"] as? [String: Any])?["full_name"] as? String ?? ""
        let title = (object["display_title"] as? String) ?? (object["name"] as? String) ?? "Workflow run"
        return WorkflowRun(id: id, repository: repository, title: title, number: object["run_number"] as? Int ?? 0,
                           state: WorkflowState(status: object["status"] as? String, conclusion: object["conclusion"] as? String),
                           url: url, createdAt: created, startedAt: date(object["run_started_at"]),
                           actor: (object["actor"] as? [String: Any])?["login"] as? String, event: object["event"] as? String)
    }

    public static func jobs(_ data: Data) -> [WorkflowJob] {
        (dictionary(data)?["jobs"] as? [[String: Any]] ?? []).compactMap { object in
            guard let id = object["id"] as? Int, let name = object["name"] as? String else { return nil }
            let steps = (object["steps"] as? [[String: Any]] ?? []).compactMap { step -> WorkflowStep? in
                guard let name = step["name"] as? String else { return nil }
                return WorkflowStep(number: step["number"] as? Int ?? 0, name: name,
                                    state: WorkflowState(status: step["status"] as? String, conclusion: step["conclusion"] as? String),
                                    startedAt: date(step["started_at"]), completedAt: date(step["completed_at"]))
            }.sorted { $0.number < $1.number }
            return WorkflowJob(id: id, name: name, state: WorkflowState(status: object["status"] as? String, conclusion: object["conclusion"] as? String),
                               url: (object["html_url"] as? String).flatMap(URL.init(string:)), steps: steps)
        }
    }

    /// The environments waiting for this user's approval: their ids, and
    /// their names for the card; `others`: those only someone else may
    /// approve.
    public static func approvable(_ data: Data) -> (ids: [Int], names: [String], others: [String]) {
        let pending = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        var ids: [Int] = [], names: [String] = [], others: [String] = []
        for item in pending {
            guard let environment = item["environment"] as? [String: Any], let id = environment["id"] as? Int else { continue }
            let name = environment["name"] as? String ?? "environment"
            if item["current_user_can_approve"] as? Bool == true {
                ids.append(id)
                names.append(name)
            } else {
                others.append(name)
            }
        }
        return (ids, names, others)
    }

    /// The release a run published: the newest one, not a draft, published
    /// since the run started.
    public static func release(in data: Data, since: Date) -> WorkflowRelease? {
        let releases = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return releases.compactMap { object -> WorkflowRelease? in
            guard object["draft"] as? Bool != true, let tag = object["tag_name"] as? String,
                  let url = (object["html_url"] as? String).flatMap(URL.init(string:)),
                  let published = date(object["published_at"]), published >= since else { return nil }
            let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag
            return WorkflowRelease(tag: tag, name: name, url: url, publishedAt: published)
        }.max { $0.publishedAt < $1.publishedAt }
    }
}

/// A followed run as it stands: what the menu bar item says, the menu's
/// lines, and what the end card says.
public struct WorkflowProgress: Equatable, Sendable {
    public var run: WorkflowRun
    public var jobs: [WorkflowJob]
    public var release: WorkflowRelease?
    /// Environments only someone else may approve (the run waits on them).
    public var waitingOn: [String] = []

    public init(run: WorkflowRun, jobs: [WorkflowJob] = [], release: WorkflowRelease? = nil, waitingOn: [String] = []) {
        self.run = run
        self.jobs = jobs
        self.release = release
        self.waitingOn = waitingOn
    }

    /// The jobs that run: a job skipped by its `if` is left out.
    public var shownJobs: [WorkflowJob] { jobs.filter { $0.state != .skipped } }

    private var steps: [WorkflowStep] { shownJobs.flatMap(\.steps) }

    /// Steps finished, of those GitHub listed so far (a job lists its steps
    /// once it starts).
    public var done: Int { steps.filter { $0.state.isDone }.count }
    public var total: Int { steps.count }

    /// The step running now ("Build, notarize, publish").
    public var current: WorkflowStep? { steps.first { $0.state == .running } }

    /// The step that failed, else the job.
    public var failedAt: String? {
        if let step = steps.first(where: { $0.state == .failed }) { return step.name }
        return shownJobs.first { $0.state == .failed }?.name
    }

    /// Beside the menu bar's icon: "Waiting", "Queued", "3/7", "Done".
    public var label: String {
        switch run.state {
        case .waiting: "Waiting"
        case .queued: "Queued"
        case .running: total == 0 ? "Starting" : "\(done)/\(total)"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        }
    }

    /// The menu's first line: "Release patch #12 · Build, notarize, publish".
    public var headline: String {
        let title = "\(run.title)" + (run.number > 0 ? " #\(run.number)" : "")
        switch run.state {
        case .waiting:
            return waitingOn.isEmpty ? "\(title) · waiting" : "\(title) · waiting for approval of \(waitingOn.joined(separator: ", "))"
        case .queued: return "\(title) · queued"
        case .running: return current.map { "\(title) · \($0.name)" } ?? "\(title) · starting"
        case .succeeded: return "\(title) · done"
        case .failed: return "\(title) · failed" + (failedAt.map { " at \($0)" } ?? "")
        case .cancelled: return "\(title) · cancelled"
        case .skipped: return "\(title) · skipped"
        }
    }

    /// What `run_github_workflow` and `get_github_workflow_run` answer:
    /// the headline, the link, each job and its steps, the release.
    public var report: String {
        var lines = [headline, run.url.absoluteString]
        if let release { lines.append("Release: \(release.name) — \(release.url.absoluteString)") }
        for job in shownJobs {
            lines.append("\(job.state.rawValue) — \(job.name)")
            lines += job.steps.map { "  \($0.state.rawValue) — \($0.name)" }
        }
        return lines.joined(separator: "\n")
    }

    /// The end card: its title and its text.
    public var ending: (title: String, text: String) {
        let place = run.repository.isEmpty ? "" : " on \(run.repository)"
        switch run.state {
        case .succeeded:
            if let release {
                return ("\(release.name) published", "\(run.title)\(place) finished: [\(release.tag)](\(release.url.absoluteString)).")
            }
            return ("\(run.title) finished", "Every step passed\(place). [The run](\(run.url.absoluteString)).")
        case .cancelled:
            return ("\(run.title) cancelled", "[The run](\(run.url.absoluteString))\(place) was cancelled.")
        default:
            let at = failedAt.map { " at **\($0)**" } ?? ""
            return ("\(run.title) failed", "It stopped\(at)\(place). [Its log](\((failedJob?.url ?? run.url).absoluteString)).")
        }
    }

    /// Where ↩ goes on the end card: the release, else the failed job's
    /// log, else the run.
    public var endLink: URL {
        if run.state == .succeeded, let release { return release.url }
        if run.state == .failed, let url = failedJob?.url { return url }
        return run.url
    }

    private var failedJob: WorkflowJob? {
        shownJobs.first { $0.state == .failed || $0.steps.contains { $0.state == .failed } }
    }
}
