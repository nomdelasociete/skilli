@testable import SkilliCore
import XCTest

/// docs/github-workflow-runs.md: what is started, GitHub's answers read,
/// what the menu bar item and the end card say.
final class GitHubWorkflowRunTests: XCTestCase {
    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func runObject(id: Int = 42, status: String, conclusion: String? = nil, created: String = "2026-10-30T10:00:05Z",
                           actor: String = "maintainer", event: String = "workflow_dispatch") -> [String: Any] {
        var object: [String: Any] = [
            "id": id, "display_title": "Release patch", "run_number": 12, "status": status,
            "html_url": "https://github.com/nomdelasociete/skilli/actions/runs/\(id)", "created_at": created,
            "run_started_at": created, "actor": ["login": actor], "event": event,
            "repository": ["full_name": "nomdelasociete/skilli"]
        ]
        if let conclusion { object["conclusion"] = conclusion }
        return object
    }

    private func job(_ name: String, status: String, conclusion: String? = nil, steps: [(String, String, String?)]) -> [String: Any] {
        var object: [String: Any] = ["id": name.count, "name": name, "status": status, "html_url": "https://github.com/nomdelasociete/skilli/actions/runs/42/job/\(name.count)"]
        if let conclusion { object["conclusion"] = conclusion }
        object["steps"] = steps.enumerated().map { index, step -> [String: Any] in
            var item: [String: Any] = ["number": index + 1, "name": step.0, "status": step.1]
            if let conclusion = step.2 { item["conclusion"] = conclusion }
            return item
        }
        return object
    }

    // MARK: What is started

    func testADispatchIsCheckedBeforeAnythingIsAsked() throws {
        let dispatch = try WorkflowDispatch(repository: " nomdelasociete/skilli ", workflow: "release.yml", ref: "main",
                                            inputs: ["bump": "patch", "critical": "false"])
        XCTAssertEqual(dispatch.repository, "nomdelasociete/skilli")
        XCTAssertEqual(dispatch.said, "release.yml on nomdelasociete/skilli main")
        XCTAssertEqual(dispatch.saidInputs, "bump: patch · critical: false")
        XCTAssertTrue(dispatch.asked.contains("approved too when you may approve it"))
        XCTAssertNil(try WorkflowDispatch(repository: "a/b", workflow: "ci.yml", ref: "").ref)
        for (repository, workflow, ref) in [("skilli", "release.yml", "main"), ("a/b/c", "release.yml", "main"), ("a/b", "../x.yml", "main"),
                                            ("a/b", "release.yml", "main..x"), ("a/b", "release.yml", "-x y"), ("a/b", "", "main")] {
            XCTAssertThrowsError(try WorkflowDispatch(repository: repository, workflow: workflow, ref: ref), "\(repository) \(workflow) \(ref)")
        }
        XCTAssertThrowsError(try WorkflowDispatch(repository: "a/b", workflow: "x.yml", inputs: ["a b": "1"]))
        let many = Dictionary(uniqueKeysWithValues: (0...25).map { ("i\($0)", "1") })
        XCTAssertThrowsError(try WorkflowDispatch(repository: "a/b", workflow: "x.yml", inputs: many))
    }

    func testInputsFromJSONAreTextAsGitHubTakesThem() throws {
        XCTAssertEqual(try WorkflowDispatch.inputs(fromJSON: #"{"bump":"minor","critical":true,"tries":3}"#),
                       ["bump": "minor", "critical": "true", "tries": "3"])
        XCTAssertEqual(try WorkflowDispatch.inputs(fromJSON: "  "), [:])
        XCTAssertThrowsError(try WorkflowDispatch.inputs(fromJSON: "bump=patch"))
        XCTAssertThrowsError(try WorkflowDispatch.inputs(fromJSON: #"{"list":[1]}"#))
    }

    func testTheLinkCarriesTheInputsAndReadsBack() throws {
        let dispatch = try WorkflowDispatch(repository: "nomdelasociete/skilli", workflow: "release.yml", ref: "main",
                                            inputs: ["bump": "patch", "critical": "true"])
        let url = SkilliLink.workflow(dispatch).url
        XCTAssertEqual(url.absoluteString,
                       "skilli://github/workflow?repo=nomdelasociete%2Fskilli&workflow=release%2Eyml&ref=main&bump=patch&critical=true")
        XCTAssertEqual(SkilliLink.parse(url), .workflow(dispatch))
        let bare = URL(string: "skilli://github/workflow?repo=a/b&workflow=ci.yml")!
        XCTAssertEqual(SkilliLink.parse(bare), .workflow(try WorkflowDispatch(repository: "a/b", workflow: "ci.yml")))
        // No repository, an input twice, another GitHub link: no link.
        for text in ["skilli://github/workflow?workflow=ci.yml", "skilli://github/workflow?repo=a/b&workflow=ci.yml&x=1&x=2",
                     "skilli://github/pulls?repo=a/b"] {
            XCTAssertNil(SkilliLink.parse(URL(string: text)!), text)
        }
    }

    func testTheReleaseSkillieIsASkillieWithItsThreeChoices() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("script/release/release.skilli").path
        let skillie = try XCTUnwrap(ScriptCommand.parse(try String(contentsOfFile: path, encoding: .utf8), path: path))
        XCTAssertEqual(skillie.title, "Release skil.li")
        XCTAssertEqual(skillie.arguments.first?.choices.map(\.value), ["patch", "minor", "critical"])
    }

    // MARK: GitHub's answers

    func testStatesFromStatusAndConclusion() {
        XCTAssertEqual(WorkflowState(status: "queued", conclusion: nil), .queued)
        XCTAssertEqual(WorkflowState(status: "pending", conclusion: nil), .queued)
        XCTAssertEqual(WorkflowState(status: "waiting", conclusion: nil), .waiting)
        XCTAssertEqual(WorkflowState(status: "in_progress", conclusion: nil), .running)
        XCTAssertEqual(WorkflowState(status: "completed", conclusion: "success"), .succeeded)
        XCTAssertEqual(WorkflowState(status: "completed", conclusion: "skipped"), .skipped)
        XCTAssertEqual(WorkflowState(status: "completed", conclusion: "cancelled"), .cancelled)
        XCTAssertEqual(WorkflowState(status: "completed", conclusion: "timed_out"), .failed)
        XCTAssertEqual(WorkflowState(status: "completed", conclusion: "startup_failure"), .failed)
    }

    func testTheDispatchedRunIsThisUsersNewOne() {
        let since = try! Date("2026-10-30T10:00:00Z", strategy: .iso8601)
        let list = json(["workflow_runs": [
            runObject(id: 1, status: "completed", conclusion: "success", created: "2026-10-29T10:00:00Z"),
            runObject(id: 2, status: "queued", created: "2026-10-30T10:00:03Z", actor: "someone-else"),
            runObject(id: 3, status: "queued", created: "2026-10-30T10:00:04Z", event: "push"),
            runObject(id: 4, status: "queued", created: "2026-10-30T10:00:02Z", actor: "Maintainer")
        ]])
        XCTAssertEqual(GitHubWorkflowAnswers.dispatchedRun(in: list, by: "maintainer", since: since)?.id, 4)
        XCTAssertNil(GitHubWorkflowAnswers.dispatchedRun(in: list, by: "nobody", since: since))
        XCTAssertEqual(GitHubWorkflowAnswers.dispatchedRunID(json(["workflow_run_id": 77, "html_url": "x"])), 77)
        XCTAssertNil(GitHubWorkflowAnswers.dispatchedRunID(Data()))
    }

    func testOnlyTheEnvironmentsThisUserMayApprove() {
        let pending = json([
            ["environment": ["id": 7, "name": "release"], "current_user_can_approve": true],
            ["environment": ["id": 8, "name": "store"], "current_user_can_approve": false]
        ])
        let read = GitHubWorkflowAnswers.approvable(pending)
        XCTAssertEqual(read.ids, [7])
        XCTAssertEqual(read.names, ["release"])
        XCTAssertEqual(read.others, ["store"])
    }

    func testTheReleaseIsOnePublishedDuringTheRun() {
        let since = try! Date("2026-10-30T10:00:00Z", strategy: .iso8601)
        let releases = json([
            ["tag_name": "v0.3.3-1600", "name": "skil.li 0.3.3 (1600)", "draft": true, "html_url": "https://x/draft", "published_at": NSNull()],
            ["tag_name": "v0.3.2-1570", "name": "skil.li 0.3.2 (1570)", "draft": false,
             "html_url": "https://github.com/nomdelasociete/skilli/releases/tag/v0.3.2-1570", "published_at": "2026-10-30T10:14:00Z"],
            ["tag_name": "v0.3.1-1557", "name": "skil.li 0.3.1 (1557)", "draft": false,
             "html_url": "https://github.com/nomdelasociete/skilli/releases/tag/v0.3.1-1557", "published_at": "2026-10-29T18:56:51Z"]
        ])
        XCTAssertEqual(GitHubWorkflowAnswers.release(in: releases, since: since)?.tag, "v0.3.2-1570")
        XCTAssertNil(GitHubWorkflowAnswers.release(in: releases, since: since.addingTimeInterval(3600)))
    }

    func testARunsLinkNamesItsRepositoryAndId() {
        XCTAssertEqual(WorkflowRun.parse(link: "https://github.com/nomdelasociete/skilli/actions/runs/123")?.id, 123)
        XCTAssertEqual(WorkflowRun.parse(link: " https://github.com/a/b/actions/runs/9/job/1 ")?.repository, "a/b")
        XCTAssertNil(WorkflowRun.parse(link: "https://example.com/a/b/actions/runs/9"))
        XCTAssertNil(WorkflowRun.parse(link: "123"))
    }

    // MARK: What it says

    private func progress(_ run: [String: Any], jobs: [[String: Any]]) -> WorkflowProgress {
        WorkflowProgress(run: GitHubWorkflowAnswers.run(json(run))!, jobs: GitHubWorkflowAnswers.jobs(json(["jobs": jobs])))
    }

    func testWhileItRunsTheItemSaysTheStepsDone() {
        let running = progress(runObject(status: "in_progress"), jobs: [
            job("check", status: "completed", conclusion: "skipped", steps: []),
            job("release", status: "in_progress", steps: [("Set up job", "completed", "success"), ("Xcode 27.1, XcodeGen", "completed", "success"),
                                                          ("Build, notarize, publish", "in_progress", nil), ("Forget the credentials", "queued", nil)])
        ])
        XCTAssertEqual(running.shownJobs.map(\.name), ["release"])
        XCTAssertEqual(running.label, "2/4")
        XCTAssertEqual(running.headline, "Release patch #12 · Build, notarize, publish")
        XCTAssertTrue(running.report.contains("  running — Build, notarize, publish"))
        var waiting = progress(runObject(status: "waiting"), jobs: [])
        waiting.waitingOn = ["release"]
        XCTAssertEqual(waiting.label, "Waiting")
        XCTAssertEqual(waiting.headline, "Release patch #12 · waiting for approval of release")
        XCTAssertEqual(progress(runObject(status: "in_progress"), jobs: []).label, "Starting")
    }

    func testTheEndCardSaysTheReleaseOrWhereItFailed() {
        var done = progress(runObject(status: "completed", conclusion: "success"), jobs: [])
        XCTAssertEqual(done.ending.title, "Release patch finished")
        done.release = WorkflowRelease(tag: "v0.3.2-1570", name: "skil.li 0.3.2 (1570)",
                                       url: URL(string: "https://github.com/nomdelasociete/skilli/releases/tag/v0.3.2-1570")!, publishedAt: .now)
        XCTAssertEqual(done.ending.title, "skil.li 0.3.2 (1570) published")
        XCTAssertEqual(done.endLink.absoluteString, "https://github.com/nomdelasociete/skilli/releases/tag/v0.3.2-1570")
        let failed = progress(runObject(status: "completed", conclusion: "failure"), jobs: [
            job("release", status: "completed", conclusion: "failure", steps: [("Set up job", "completed", "success"),
                                                                             ("Build, notarize, publish", "completed", "failure"),
                                                                             ("Forget the credentials", "completed", "success")])
        ])
        XCTAssertEqual(failed.label, "Failed")
        XCTAssertEqual(failed.ending.title, "Release patch failed")
        XCTAssertTrue(failed.ending.text.hasPrefix("It stopped at **Build, notarize, publish** on nomdelasociete/skilli."))
        XCTAssertEqual(failed.endLink.absoluteString, "https://github.com/nomdelasociete/skilli/actions/runs/42/job/7")
    }
}
