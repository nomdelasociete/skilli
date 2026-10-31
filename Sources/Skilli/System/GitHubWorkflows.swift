import Foundation
import SkilliCore

/// GitHub Actions workflows started from skil.li and followed until they
/// end (docs/github-workflow-runs.md). Started only once the user said yes
/// in the card (the tool and the link both ask every time), so the run's
/// environment is approved with that same yes when GitHub says the user
/// may approve it. Each run is read every few seconds while it runs, with
/// this Mac's own GitHub sign-in, then said once in the end card. Nothing
/// is kept across launches.
@MainActor
final class GitHubWorkflows {
    /// The runs followed now, newest last.
    private(set) var followed: [WorkflowProgress] = []
    /// What went wrong reading a run, by its id (said in its menu; the
    /// reads go on).
    private(set) var problems: [Int: String] = [:]
    /// The menu bar item redraws.
    var onChange: (() -> Void)?
    /// A run ended: the end card.
    var onFinished: ((WorkflowProgress) -> Void)?

    /// Self-test hooks: how often a run is read (6 times less while every
    /// run only waits), how long a started run is
    /// looked for when GitHub's answer does not name it.
    var interval: Duration = .seconds(5)
    var findFor: Duration = .seconds(30)

    private let github: () -> GitHubBook?
    /// Environments approved, by run: each once.
    private var approved: [Int: Set<Int>] = [:]
    private var loop: Task<Void, Never>?

    init(github: @escaping () -> GitHubBook?) {
        self.github = github
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Starts `dispatch`, finds its run, follows it; its state now. The
    /// caller asked the user first.
    func start(_ dispatch: WorkflowDispatch) async throws -> WorkflowProgress {
        let book = try signedIn()
        let repo = "repos/\(dispatch.repository)"
        let ref: String
        if let given = dispatch.ref {
            ref = given
        } else {
            let data = try await book.rest("GET", repo)
            guard let branch = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["default_branch"] as? String else {
                throw Failure(message: "GitHub did not say \(dispatch.repository)'s default branch: give ref.")
            }
            ref = branch
        }
        let since = Date.now
        let answer = try await book.rest("POST", "\(repo)/actions/workflows/\(dispatch.workflow)/dispatches",
                                         body: ["ref": ref, "inputs": dispatch.inputs])
        Log.actions.notice("GitHub: started \(dispatch.workflow, privacy: .public) on \(dispatch.repository, privacy: .private)")
        var run: WorkflowRun?
        if let id = GitHubWorkflowAnswers.dispatchedRunID(answer) {
            run = GitHubWorkflowAnswers.run(try await book.rest("GET", "\(repo)/actions/runs/\(id)"))
        } else {
            let login = try await self.login(book)
            let deadline = ContinuousClock.now + findFor
            while run == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .seconds(2))
                let list = try await book.rest("GET", "\(repo)/actions/workflows/\(dispatch.workflow)/runs",
                                               query: [URLQueryItem(name: "event", value: "workflow_dispatch"),
                                                       URLQueryItem(name: "branch", value: ref),
                                                       URLQueryItem(name: "per_page", value: "10")])
                run = GitHubWorkflowAnswers.dispatchedRun(in: list, by: login, since: since)
            }
        }
        guard let run else {
            throw Failure(message: "Started, but GitHub showed no new run of \(dispatch.workflow) within \(findFor.components.seconds) s: "
                          + "\(dispatch.runsPage.absoluteString)")
        }
        var progress = WorkflowProgress(run: run.named(dispatch.repository))
        followed.append(progress)
        approved[run.id] = []
        progress = await read(progress, in: book)
        replace(progress)
        follow()
        return progress
    }

    /// A run's state, by its link: the followed one's, else read now.
    func state(of link: String) async throws -> WorkflowProgress {
        guard let (repository, id) = WorkflowRun.parse(link: link) else {
            throw Failure(message: "“\(link)” is not a run's link: https://github.com/owner/name/actions/runs/<id>.")
        }
        if let known = followed.first(where: { $0.run.id == id }) { return known }
        let book = try signedIn()
        guard let run = GitHubWorkflowAnswers.run(try await book.rest("GET", "repos/\(repository)/actions/runs/\(id)")) else {
            throw Failure(message: "GitHub did not give run \(id) of \(repository).")
        }
        return try await details(WorkflowProgress(run: run.named(repository)), in: book)
    }

    /// Cancel Run, from its menu: GitHub stops it; the next read says so.
    func cancel(_ id: Int) {
        guard let progress = followed.first(where: { $0.run.id == id }), let book = github() else { return }
        Task {
            do {
                _ = try await book.rest("POST", "repos/\(progress.run.repository)/actions/runs/\(id)/cancel")
                Log.actions.notice("GitHub: cancelled run \(id)")
            } catch {
                problems[id] = error.localizedDescription
                onChange?()
            }
        }
    }

    // MARK: Following

    private func follow() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while let self, !self.followed.isEmpty, !Task.isCancelled {
                // Only waiting (for someone else's approval, a runner): a
                // run GitHub may hold for days is read 6 times less often.
                let idle = self.followed.allSatisfy { [.waiting, .queued].contains($0.run.state) }
                try? await Task.sleep(for: idle ? self.interval * 6 : self.interval)
                await self.readAll()
            }
            self?.loop = nil
        }
    }

    private func readAll() async {
        guard let book = github(), book.isSignedIn else {
            for progress in followed { problems[progress.run.id] = "Signed out of GitHub: Settings → GitHub." }
            onChange?()
            return
        }
        for progress in followed {
            let now = await read(progress, in: book)
            replace(now)
            if now.run.state.isDone { finish(now) }
        }
    }

    /// The run read again, its environment approved when it waits for the
    /// user, the release it made once it succeeded.
    private func read(_ progress: WorkflowProgress, in book: GitHubBook) async -> WorkflowProgress {
        do {
            let next = try await details(progress, in: book)
            problems[next.run.id] = nil
            guard next.run.state == .waiting else { return next }
            return try await approve(next, in: book)
        } catch {
            problems[progress.run.id] = error.localizedDescription
            return progress
        }
    }

    /// The run, its jobs and steps; once it succeeded, the release it
    /// published.
    private func details(_ progress: WorkflowProgress, in book: GitHubBook) async throws -> WorkflowProgress {
        let repo = "repos/\(progress.run.repository)"
        guard let run = GitHubWorkflowAnswers.run(try await book.rest("GET", "\(repo)/actions/runs/\(progress.run.id)")) else {
            throw Failure(message: "GitHub did not give the run.")
        }
        var next = progress
        next.run = run.named(progress.run.repository)
        next.jobs = GitHubWorkflowAnswers.jobs(try await book.rest("GET", "\(repo)/actions/runs/\(run.id)/jobs",
                                                                   query: [URLQueryItem(name: "filter", value: "latest")]))
        // The release only adds a link to the end card: one not read never
        // keeps a finished run followed.
        if run.state == .succeeded, next.release == nil,
           let releases = try? await book.rest("GET", "\(repo)/releases", query: [URLQueryItem(name: "per_page", value: "5")]) {
            next.release = GitHubWorkflowAnswers.release(in: releases, since: run.startedAt ?? run.createdAt)
        }
        return next
    }

    private func approve(_ progress: WorkflowProgress, in book: GitHubBook) async throws -> WorkflowProgress {
        let path = "repos/\(progress.run.repository)/actions/runs/\(progress.run.id)/pending_deployments"
        let pending = GitHubWorkflowAnswers.approvable(try await book.rest("GET", path))
        var next = progress
        next.waitingOn = pending.others
        let done = approved[progress.run.id] ?? []
        let ids = pending.ids.filter { !done.contains($0) }
        guard !ids.isEmpty else { return next }
        _ = try await book.rest("POST", path, body: ["environment_ids": ids, "state": "approved",
                                                     "comment": "Approved in skil.li when the run was started."])
        approved[progress.run.id, default: []].formUnion(ids)
        Log.actions.notice("GitHub: approved \(pending.names.joined(separator: ", "), privacy: .public) for run \(progress.run.id)")
        return next
    }

    private func finish(_ progress: WorkflowProgress) {
        followed.removeAll { $0.run.id == progress.run.id }
        approved[progress.run.id] = nil
        problems[progress.run.id] = nil
        Log.actions.notice("GitHub: run \(progress.run.id) ended \(progress.run.state.rawValue, privacy: .public)")
        onChange?()
        onFinished?(progress)
    }

    private func replace(_ progress: WorkflowProgress) {
        guard let index = followed.firstIndex(where: { $0.run.id == progress.run.id }) else { return }
        if followed[index] != progress {
            followed[index] = progress
        }
        onChange?()
    }

    // MARK: Helpers

    private func signedIn() throws -> GitHubBook {
        guard let book = github(), book.isSignedIn else {
            throw Failure(message: "GitHub is not connected. The user signs in with GitHub in skil.li's Settings → GitHub.")
        }
        return book
    }

    /// Who started it, to find the run: the login read with the pull
    /// requests, else GitHub's `/user`.
    private func login(_ book: GitHubBook) async throws -> String {
        if let login = book.login { return login }
        guard let login = GitHubWorkflowAnswers.login(try await book.rest("GET", "user")) else {
            throw Failure(message: "GitHub did not say who is signed in.")
        }
        return login
    }
}
