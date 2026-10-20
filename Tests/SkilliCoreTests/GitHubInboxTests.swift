import XCTest
@testable import SkilliCore

final class GitHubInboxTests: XCTestCase {
    /// GitHub's answer to `GitHubInbox.query`, shaped like the real one.
    private func response(viewer: [String], search: [String] = [], errors: String? = nil) -> Data {
        let data = #"{"viewer":{"login":"jb","pullRequests":{"nodes":[\#(viewer.joined(separator: ","))]}},"search":{"nodes":[\#(search.joined(separator: ","))]}}"#
        return Data((errors.map { #"{"data":null,"errors":[{"message":"\#($0)"}]}"# } ?? #"{"data":\#(data)}"#).utf8)
    }

    private func node(_ number: Int, repo: String = "nomdelasociete/skilli", author: String = "jb", draft: Bool = false, archived: Bool = false,
                      decision: String? = "APPROVED", mergeState: String = "CLEAN", mergeable: String = "MERGEABLE", rollup: String? = nil,
                      contexts: [String] = [], reviewers: [String] = [], created: String = "2026-10-10T08:00:00Z",
                      permission: String = "WRITE") -> String {
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        let decisionJSON = decision.map { "\"\($0)\"" } ?? "null"
        let rollupJSON = rollup.map { #"{"state":"\#($0)","contexts":{"nodes":[\#(contexts.joined(separator: ","))]}}"# } ?? "null"
        let requests = reviewers.map { #"{"requestedReviewer":{"__typename":"User","login":"\#($0)"}}"# }.joined(separator: ",")
        return #"""
            {"databaseId":\#(number * 1000),"number":\#(number),"title":"PR \#(number)","url":"https://github.com/\#(repo)/pull/\#(number)",
             "state":"OPEN","isDraft":\#(draft),"createdAt":"\#(created)","updatedAt":"2026-10-12T08:00:00Z","author":{"login":"\#(author)"},
             "headRefOid":"abc\#(number)","repository":{"nameWithOwner":"\#(repo)","name":"\#(name)","isArchived":\#(archived),"viewerDefaultMergeMethod":"SQUASH","viewerPermission":"\#(permission)"},
             "reviewDecision":\#(decisionJSON),"mergeStateStatus":"\#(mergeState)","mergeable":"\#(mergeable)",
             "reviewRequests":{"nodes":[\#(requests)]},"latestReviews":{"nodes":[]},
             "commits":{"nodes":[{"commit":{"statusCheckRollup":\#(rollupJSON)}}]}}
            """#
    }

    private let woodpeckerRunning = #"{"__typename":"StatusContext","context":"ci/woodpecker/pr/build","state":"PENDING"}"#
    private let vercelFailed = #"{"__typename":"StatusContext","context":"Vercel","state":"FAILURE"}"#
    private let checkGreen = #"{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}"#
    private let checkFailed = #"{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"FAILURE"}"#

    func testGroupsFromOneAnswer() throws {
        let data = response(viewer: [
            node(1, rollup: "SUCCESS", contexts: [checkGreen]),
            node(2, mergeState: "BLOCKED", rollup: "PENDING", contexts: [woodpeckerRunning]),
            node(3, mergeState: "UNSTABLE", rollup: "FAILURE", contexts: [vercelFailed]),
            node(4, mergeState: "DIRTY", mergeable: "CONFLICTING"),
            node(5, draft: true),
            node(6, archived: true),
            node(7, mergeState: "BEHIND", rollup: "SUCCESS", contexts: [checkGreen]),
            node(8, mergeState: "BLOCKED", rollup: "FAILURE", contexts: [checkFailed, checkGreen])
        ], search: [
            // Waiting for my review, in another repository; and #1 again.
            node(9, repo: "nimbus-hq/nimbus", author: "lea", decision: "REVIEW_REQUIRED", mergeState: "BLOCKED", reviewers: ["jb"]),
            node(1, rollup: "SUCCESS", contexts: [checkGreen]),
            "{}"
        ])
        let (login, pullRequests) = try GitHubInbox.pullRequests(fromResponse: data)
        XCTAssertEqual(login, "jb")
        let byNumber = Dictionary(uniqueKeysWithValues: pullRequests.map { ($0.number, $0) })
        // Once each; the archived one and the empty search node left out.
        XCTAssertEqual(pullRequests.count, 8)
        XCTAssertNil(byNumber[6])

        XCTAssertEqual(byNumber[1]?.group, .ready)
        XCTAssertEqual(byNumber[1]?.defaultMergeMethod, .squash)
        XCTAssertTrue(byNumber[1]?.canMerge == true)
        XCTAssertEqual(byNumber[1]?.id, 1000)
        XCTAssertEqual(byNumber[1]?.reason, "Approved, ready to merge")
        // Woodpecker posts commit statuses: named while it runs.
        XCTAssertEqual(byNumber[2]?.group, .testing)
        XCTAssertEqual(byNumber[2]?.reason, "ci/woodpecker/pr/build running")
        // Mergeable with a red check that is not required: never ready.
        XCTAssertEqual(byNumber[3]?.group, .blocked)
        XCTAssertEqual(byNumber[3]?.reason, "Vercel failed (not required)")
        XCTAssertEqual(byNumber[4]?.reason, "Merge conflict")
        XCTAssertEqual(byNumber[5]?.reason, "Draft")
        // Behind: not ready until updated, which is offered.
        XCTAssertEqual(byNumber[7]?.group, .blocked)
        XCTAssertTrue(byNumber[7]?.canUpdateBranch == true)
        XCTAssertFalse(byNumber[7]?.canMerge == true)
        XCTAssertEqual(byNumber[8]?.reason, "lint failed")
        XCTAssertEqual(byNumber[9]?.group, .waiting)
        XCTAssertEqual(byNumber[9]?.statusLabel, "Your review")
        XCTAssertTrue(byNumber[9]?.needsUserAction == true)
        XCTAssertFalse(byNumber[9]?.isAuthor == true)

        // Ready first, then blocked, waiting, testing.
        XCTAssertEqual(pullRequests.map(\.group), [.ready, .blocked, .blocked, .blocked, .blocked, .blocked, .waiting, .testing])
        XCTAssertEqual(GitHubInbox.summary(pullRequests), "1 ready · 5 blocked · 1 waiting · 1 testing")
        XCTAssertEqual(GitHubInbox.summary([]), "")
    }

    /// Green only when the user can merge: a clean pull request in someone
    /// else's repository waits for its maintainers.
    func testReadyOnlyWhenTheUserCanMerge() throws {
        let data = response(viewer: [node(1, repo: "omacom/omarchy", permission: "READ"), node(2, permission: "MAINTAIN")])
        let byNumber = Dictionary(uniqueKeysWithValues: try GitHubInbox.pullRequests(fromResponse: data).pullRequests.map { ($0.number, $0) })
        XCTAssertEqual(byNumber[1]?.group, .waiting)
        XCTAssertEqual(byNumber[1]?.statusLabel, "Maintainers' turn")
        XCTAssertFalse(byNumber[1]?.canMerge == true)
        XCTAssertEqual(byNumber[2]?.group, .ready)
        XCTAssertTrue(byNumber[2]?.canMerge == true)
    }

    func testOldestFirstWithinAGroup() throws {
        let data = response(viewer: [node(1, created: "2026-10-11T08:00:00Z"), node(2, created: "2026-09-01T08:00:00Z")])
        XCTAssertEqual(try GitHubInbox.pullRequests(fromResponse: data).pullRequests.map(\.number), [2, 1])
    }

    func testGitHubErrorIsSaid() {
        XCTAssertThrowsError(try GitHubInbox.pullRequests(fromResponse: response(viewer: [], errors: "Bad credentials"))) { error in
            XCTAssertEqual(error.localizedDescription, "Bad credentials")
        }
    }

    func testNotifications() throws {
        let json = #"""
            [{"id":"11","reason":"review_requested","unread":true,"updated_at":"2026-10-12T09:00:00Z",
              "subject":{"title":"Add the GitHub skillie","url":"https://api.github.com/repos/nomdelasociete/skilli/pulls/94","type":"PullRequest"},
              "repository":{"full_name":"nomdelasociete/skilli"}},
             {"id":"12","reason":"ci_activity","unread":false,"updated_at":"2026-10-12T10:00:00Z",
              "subject":{"title":"CI failed on main","url":null,"type":"CheckSuite"},
              "repository":{"full_name":"nimbus-hq/nimbus"}},
             {"id":"13","reason":"mention","unread":true,"updated_at":"2026-10-11T10:00:00Z",
              "subject":{"title":"Crash on wake","url":"https://api.github.com/repos/o/r/issues/7","type":"Issue"},
              "repository":{"full_name":"o/r"}}]
            """#
        let notifications = try GitHubNotifications.parse(Data(json.utf8))
        XCTAssertEqual(notifications.map(\.id), ["12", "11", "13"])
        XCTAssertEqual(notifications[1].url.absoluteString, "https://github.com/nomdelasociete/skilli/pull/94")
        XCTAssertEqual(notifications[1].reasonTitle, "Review requested")
        XCTAssertEqual(notifications[0].url.absoluteString, "https://github.com/nimbus-hq/nimbus/actions")
        XCTAssertEqual(notifications[2].url.absoluteString, "https://github.com/o/r/issues/7")
        XCTAssertEqual(GitHubNotifications.webURL(subject: "https://api.github.com/repos/o/r/commits/abc", type: "Commit", repository: "o/r").absoluteString,
                       "https://github.com/o/r/commit/abc")
        XCTAssertEqual(GitHubNotifications.webURL(subject: "https://api.github.com/repos/o/r/releases/123", type: "Release", repository: "o/r").absoluteString,
                       "https://github.com/o/r/releases")
    }
}
