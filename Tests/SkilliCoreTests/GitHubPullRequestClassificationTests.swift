import XCTest
@testable import SkilliCore

/// Where a pull request stands comes from GitHub's own merge box
/// (`mergeStateStatus`); the review decision and the checks only say why,
/// the viewer's rights whether "ready" is theirs.
final class GitHubPullRequestClassificationTests: XCTestCase {
    private func classify(_ change: (inout PullRequestFacts) -> Void) -> PullRequestClassification {
        var facts = PullRequestFacts(mergeStateStatus: "CLEAN", mergeable: "MERGEABLE", isAuthor: true, viewerCanMerge: true, viewerCanUpdateBranch: true)
        change(&facts)
        return GitHubInbox.classify(facts)
    }

    func testCleanIsReadyOnlyForWhoCanMerge() {
        XCTAssertEqual(classify { _ in }.group, .ready)
        XCTAssertEqual(classify { $0.mergeStateStatus = "HAS_HOOKS" }.group, .ready)
        XCTAssertEqual(classify { $0.reviewDecision = "APPROVED" }.reason, "Approved, ready to merge")
        let theirs = classify { $0.viewerCanMerge = false }
        XCTAssertEqual(theirs.group, .waiting)
        XCTAssertEqual(theirs.statusLabel, "Maintainers' turn")
        XCTAssertFalse(theirs.needsUserAction)
    }

    func testNothingButCleanIsReady() {
        for state in ["BLOCKED", "BEHIND", "DIRTY", "UNSTABLE", "UNKNOWN", "SOMETHING_NEW"] {
            XCTAssertNotEqual(classify { $0.mergeStateStatus = state; $0.checks = "SUCCESS"; $0.reviewDecision = "APPROVED" }.group, .ready, state)
        }
        XCTAssertNotEqual(classify { $0.mergeStateStatus = nil }.group, .ready)
    }

    func testDraftAndConflictAreTheAuthorsTurn() {
        let draft = classify { $0.isDraft = true }
        XCTAssertEqual(draft.group, .blocked)
        XCTAssertEqual(draft.reason, "Draft")
        XCTAssertTrue(draft.needsUserAction)
        XCTAssertEqual(classify { $0.mergeStateStatus = "DIRTY" }.reason, "Merge conflict")
        XCTAssertEqual(classify { $0.mergeable = "CONFLICTING"; $0.mergeStateStatus = "UNKNOWN" }.reason, "Merge conflict")
        XCTAssertEqual(classify { $0.isDraft = true; $0.isAuthor = false }.statusLabel, "Draft")
    }

    func testBlockedSaysWhy() {
        func blocked(_ change: (inout PullRequestFacts) -> Void) -> PullRequestClassification {
            classify { $0.mergeStateStatus = "BLOCKED"; change(&$0) }
        }
        XCTAssertEqual(blocked { $0.reviewDecision = "CHANGES_REQUESTED" }.reason, "Changes requested")
        XCTAssertEqual(blocked { $0.checks = "FAILURE"; $0.failingCheck = "lint" }.reason, "lint failed")
        XCTAssertEqual(blocked { $0.checks = "ERROR" }.reason, "Checks failed")
        let running = blocked { $0.checks = "PENDING"; $0.runningCheck = "ci/woodpecker/pr/build" }
        XCTAssertEqual(running.group, .testing)
        XCTAssertEqual(running.reason, "ci/woodpecker/pr/build running")
        let review = blocked { $0.reviewDecision = "REVIEW_REQUIRED"; $0.checks = "SUCCESS" }
        XCTAssertEqual(review.group, .waiting)
        XCTAssertEqual(review.statusLabel, "Awaiting review")
        let mine = blocked { $0.reviewDecision = "REVIEW_REQUIRED"; $0.isAuthor = false; $0.isRequestedReviewer = true }
        XCTAssertEqual(mine.statusLabel, "Your review")
        XCTAssertTrue(mine.needsUserAction)
        XCTAssertEqual(blocked { $0.checks = "SUCCESS" }.reason, "Blocked by a branch rule")
    }

    func testBehindOffersTheUpdateWhenAllowed() {
        let behind = classify { $0.mergeStateStatus = "BEHIND" }
        XCTAssertEqual(behind.group, .blocked)
        XCTAssertTrue(behind.canUpdateBranch)
        XCTAssertEqual(behind.statusLabel, "Update branch")
        let notMine = classify { $0.mergeStateStatus = "BEHIND"; $0.viewerCanUpdateBranch = false; $0.isAuthor = false }
        XCTAssertFalse(notMine.canUpdateBranch)
        XCTAssertFalse(notMine.needsUserAction)
    }

    func testUnstableIsNeverReady() {
        let red = classify { $0.mergeStateStatus = "UNSTABLE"; $0.checks = "FAILURE"; $0.failingCheck = "Vercel" }
        XCTAssertEqual(red.group, .blocked)
        XCTAssertEqual(red.reason, "Vercel failed (not required)")
        XCTAssertEqual(classify { $0.mergeStateStatus = "UNSTABLE"; $0.checks = "PENDING" }.group, .testing)
    }

    func testGitHubStillCheckingOrMerging() {
        XCTAssertEqual(classify { $0.mergeStateStatus = "UNKNOWN" }.reason, "GitHub is checking")
        let queued = classify { $0.isInMergeQueue = true }
        XCTAssertEqual(queued.group, .testing)
        XCTAssertEqual(queued.reason, "In the merge queue")
    }
}
