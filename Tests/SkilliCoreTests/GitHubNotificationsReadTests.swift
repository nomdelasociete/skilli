import Foundation
import XCTest
@testable import SkilliCore

/// A stand-in GitHub `/notifications`: every request it got, and GitHub's
/// own behaviour, a conditional 200 listing only the threads changed since.
private actor StandInNotifications {
    var asked: [(page: Int, since: String?)] = []
    let total: Int
    let changedSince: [String]
    let unchangedSince: String?

    init(total: Int, changedSince: [String] = [], unchangedSince: String? = nil) {
        self.total = total
        self.changedSince = changedSince
        self.unchangedSince = unchangedSince
    }

    func page(_ number: Int, _ since: String?) -> GitHubNotificationsPage {
        asked.append((number, since))
        if let since {
            if since == unchangedSince { return GitHubNotificationsPage(status: 304, data: Data(), lastModified: nil, pollInterval: 60, hasNext: false) }
            return GitHubNotificationsPage(status: 200, data: Self.threads(changedSince), lastModified: "Tue, 27 Oct 2026 08:00:00 GMT",
                                           pollInterval: 60, hasNext: false)
        }
        let ids = Array(((number - 1) * 50)..<min(number * 50, total)).map { String($0 + 1) }
        return GitHubNotificationsPage(status: 200, data: Self.threads(ids), lastModified: "Tue, 27 Oct 2026 08:00:00 GMT",
                                       pollInterval: 60, hasNext: number * 50 < total)
    }

    static func threads(_ ids: [String]) -> Data {
        let list = ids.map { id -> [String: Any] in
            ["id": id, "reason": "review_requested", "unread": true, "updated_at": "2026-10-26T10:00:00Z",
             "subject": ["title": "Synthetic thread \(id)", "url": "https://api.github.com/repos/lumiere/atelier/pulls/\(id)", "type": "PullRequest"],
             "repository": ["full_name": "lumiere/atelier"]]
        }
        return try! JSONSerialization.data(withJSONObject: list)
    }
}

final class GitHubNotificationsReadTests: XCTestCase {
    private func ids(_ read: GitHubNotificationsRead) -> [String]? {
        if case .changed(let list, _, _, _) = read { return list.map(\.id) }
        return nil
    }

    func testAConditional200IsFollowedByAFullRead() async throws {
        let github = StandInNotifications(total: 330, changedSince: ["330"])
        let read = try await GitHubNotifications.read(since: "Mon, 26 Oct 2026 10:00:00 GMT") { await github.page($0, $1) }
        XCTAssertEqual(ids(read)?.count, 330, "the whole inbox, not the 1 thread changed since")
        let asked = await github.asked
        XCTAssertEqual(asked.first?.since, "Mon, 26 Oct 2026 10:00:00 GMT")
        XCTAssertEqual(asked.dropFirst().map(\.page), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertTrue(asked.dropFirst().allSatisfy { $0.since == nil }, "only the first request is conditional")
        guard case .changed(_, let complete, let modified, _) = read else { return XCTFail("changed") }
        XCTAssertTrue(complete)
        XCTAssertEqual(modified, "Tue, 27 Oct 2026 08:00:00 GMT")
    }

    func testA304CostsOneRequest() async throws {
        let github = StandInNotifications(total: 330, unchangedSince: "Tue, 27 Oct 2026 08:00:00 GMT")
        let read = try await GitHubNotifications.read(since: "Tue, 27 Oct 2026 08:00:00 GMT") { await github.page($0, $1) }
        XCTAssertEqual(read, .unchanged(pollInterval: 60))
        let asked = await github.asked
        XCTAssertEqual(asked.count, 1)
    }

    func testAShortPageWithANextLinkIsNotTheLast() async throws {
        let read = try await GitHubNotifications.read(since: nil) { number, _ in
            let ids = number == 1 ? (1...30).map(String.init) : (31...45).map(String.init)
            return GitHubNotificationsPage(status: 200, data: StandInNotifications.threads(ids), lastModified: nil, pollInterval: 60,
                                           hasNext: number == 1)
        }
        XCTAssertEqual(Set(ids(read) ?? []).count, 45)
    }

    func testEveryPageIsReadAndACutIsSaid() async throws {
        let all = StandInNotifications(total: 120)
        let read = try await GitHubNotifications.read(since: nil) { await all.page($0, $1) }
        XCTAssertEqual(Set(ids(read) ?? []).count, 120)
        let cut = StandInNotifications(total: 900)
        guard case .changed(let list, let complete, _, _) = try await GitHubNotifications.read(since: nil, maxPages: 10, page: { await cut.page($0, $1) })
        else { return XCTFail("changed") }
        XCTAssertEqual(list.count, 500)
        XCTAssertFalse(complete, "more unread than read: said, never a silent cut")
    }
}
