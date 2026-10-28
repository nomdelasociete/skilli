import Foundation
import XCTest
@testable import SkilliCore

/// A clock the tests move; read from any thread.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

/// A stand-in relay: answers by method and path, keeps every request it
/// got, and can hold one answer until released.
private actor StandInRelay {
    var requests: [URLRequest] = []
    private var replies: [String: [RelayHTTPReply]] = [:]
    private var held: [String: CheckedContinuation<Void, Never>] = [:]
    private var holding: Set<String> = []

    /// In order; the last one keeps answering.
    func answer(_ key: String, _ replies: RelayHTTPReply...) { self.replies[key, default: []] += replies }
    /// From now on, only this.
    func set(_ key: String, _ reply: RelayHTTPReply) { replies[key] = [reply] }
    func hold(_ key: String) { holding.insert(key) }
    func release(_ key: String) {
        holding.remove(key)
        held.removeValue(forKey: key)?.resume()
    }
    func count(_ key: String) -> Int { requests.filter { Self.key($0) == key }.count }

    func send(_ request: URLRequest) async throws -> RelayHTTPReply {
        requests.append(request)
        let key = Self.key(request)
        if holding.contains(key) { await withCheckedContinuation { held[key] = $0 } }
        guard var list = replies[key], !list.isEmpty else { return RelayHTTPReply(status: 503, data: Data(), retryAfter: 60) }
        let reply = list.count > 1 ? list.removeFirst() : list[0]
        replies[key] = list
        return reply
    }

    static func key(_ request: URLRequest) -> String { "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")" }
}

@MainActor
final class GitHubServerInboxTests: XCTestCase {
    private let clock = TestClock()
    private let relay = StandInRelay()
    private var subject = "10"
    private var ready = true

    private func access(subject: String? = nil) -> RelayInboxAccess {
        let relay = relay
        return RelayInboxAccess(authority: URL(string: "https://access.relay.example")!, browser: URL(string: "https://auth.relay.example")!,
                                token: "v2.device-access", subject: subject ?? self.subject, send: { try await relay.send($0) })
    }

    private func client() -> RelayInboxClient? {
        guard ready else { return nil }
        var client = RelayInboxClient(access: access())
        let clock = clock
        client.now = { clock.now }
        return client
    }

    private func inbox() -> GitHubServerInbox {
        let clock = clock
        let inbox = GitHubServerInbox(client: { nil }, now: { clock.now })
        inbox.client = { [unowned self] in self.client() }
        return inbox
    }

    // MARK: Fixtures (synthetic: Lumière's repositories, Margot Martin)

    private func pullRequest(_ number: Int, mergeState: String = "CLEAN", inQueue: Bool = false, canUpdate: Bool = false,
                             contexts: [[String: Any]] = [], totalCount: Int? = nil, drop: String? = nil) -> [String: Any] {
        var node: [String: Any] = [
            "id": "PR_\(number)", "databaseId": 1000 + number, "number": number, "title": "Synthetic change \(number)",
            "url": "https://github.com/lumiere/atelier/pull/\(number)", "state": "OPEN", "isDraft": false,
            "createdAt": "2026-10-20T09:00:0\(number % 10)Z", "updatedAt": "2026-10-26T09:00:00Z", "headRefOid": "abc\(number)",
            "author": ["login": "margot-martin"],
            "repository": ["databaseId": 200, "nameWithOwner": "lumiere/atelier", "name": "atelier", "isArchived": false,
                           "viewerPermission": "WRITE", "viewerDefaultMergeMethod": "SQUASH"],
            "reviewDecision": "APPROVED", "mergeStateStatus": mergeState, "mergeable": "MERGEABLE", "viewerCanMergeAsAdmin": false,
            "isInMergeQueue": inQueue, "viewerCanUpdateBranch": canUpdate,
            "reviewRequests": ["nodes": []], "reviews": ["nodes": []],
            "commits": ["nodes": [["commit": ["statusCheckRollup": [
                "state": contexts.isEmpty ? "SUCCESS" : "FAILURE",
                "contexts": ["totalCount": totalCount ?? contexts.count, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                             "nodes": contexts]]]]]],
        ]
        if let drop { node.removeValue(forKey: drop) }
        return node
    }

    private func snapshot(_ nodes: [[String: Any]], subject: String = "10", updatedAt: TimeInterval? = nil) -> RelayHTTPReply {
        let body: [String: Any] = ["schema": 1, "subject": subject, "login": "margot-martin", "revision": UUID().uuidString,
                                   "updatedAt": updatedAt ?? clock.now.timeIntervalSince1970,
                                   "data": ["s0": ["issueCount": nodes.count, "nodes": nodes]]]
        return RelayHTTPReply(status: 200, data: try! JSONSerialization.data(withJSONObject: body))
    }

    private func notes(_ ids: [String], complete: Bool = true, pollInterval: Int = 60, subject: String = "10") -> RelayHTTPReply {
        let threads = ids.map { id -> [String: Any] in
            ["id": id, "reason": "review_requested", "unread": true, "updated_at": "2026-10-26T10:00:00Z",
             "subject": ["title": "Synthetic thread \(id)", "url": "https://api.github.com/repos/lumiere/atelier/pulls/\(id)", "type": "PullRequest"],
             "repository": ["full_name": "lumiere/atelier"]]
        }
        let body: [String: Any] = ["schema": 1, "subject": subject, "updatedAt": clock.now.timeIntervalSince1970, "revision": UUID().uuidString,
                                   "complete": complete, "pollInterval": pollInterval, "threads": threads]
        return RelayHTTPReply(status: 200, data: try! JSONSerialization.data(withJSONObject: body))
    }

    private func settle(_ inbox: GitHubServerInbox) async {
        for _ in 0..<50 { await inbox.settled(); await Task.yield() }
    }

    // MARK: The relay's copy, classified here

    func testSnapshotIsClassifiedWithEveryFieldTheMergeBoxNeeds() async throws {
        let failing: [String: Any] = ["__typename": "StatusContext", "context": "ci/woodpecker/pr/build", "state": "FAILURE"]
        await relay.answer("GET /inbox", snapshot([pullRequest(1, inQueue: true), pullRequest(2, mergeState: "BEHIND", canUpdate: false),
                                                   pullRequest(3), pullRequest(4, mergeState: "UNSTABLE", contexts: [failing])]))
        let shown = try await client()!.inbox()
        let byNumber = Dictionary(uniqueKeysWithValues: shown.pullRequests.map { ($0.number, $0) })
        XCTAssertEqual(byNumber[1]?.group, .testing, "in the merge queue, never ready")
        XCTAssertEqual(byNumber[2]?.canUpdateBranch, false, "GitHub said the viewer may not update it")
        XCTAssertEqual(byNumber[3]?.group, .ready)
        XCTAssertEqual(byNumber[3]?.defaultMergeMethod, .squash)
        XCTAssertEqual(byNumber[4]?.reason, "ci/woodpecker/pr/build failed (not required)")
        XCTAssertEqual(shown.login, "margot-martin")
    }

    func testAnOlderRelayWithoutAClassifyingFieldIsRefusedNotGuessed() async {
        for field in ["isInMergeQueue", "viewerCanUpdateBranch", "createdAt"] {
            await relay.set("GET /inbox", snapshot([pullRequest(1, drop: field)]))
            do { _ = try await client()!.inbox(); XCTFail(field) } catch { XCTAssertEqual(error as? RelayInboxFailure, .invalidResponse, field) }
        }
        let unnamed: [String: Any] = ["__typename": "StatusContext", "state": "FAILURE"]
        await relay.set("GET /inbox", snapshot([pullRequest(1, contexts: [unnamed])]))
        do { _ = try await client()!.inbox(); XCTFail("status without context") } catch { XCTAssertEqual(error as? RelayInboxFailure, .invalidResponse) }
    }

    func testCutChecksAreRefusedNotShortened() async {
        let check: [String: Any] = ["__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"]
        await relay.answer("GET /inbox", snapshot([pullRequest(1, contexts: [check], totalCount: 150)]))
        do { _ = try await client()!.inbox(); XCTFail() } catch { XCTAssertEqual(error as? RelayInboxFailure, .invalidResponse) }
    }

    func testAnotherAccountsSnapshotShowsNothing() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]), snapshot([pullRequest(1)], subject: "11"))
        let inbox = inbox()
        inbox.readInbox()
        await settle(inbox)
        XCTAssertEqual(inbox.pullRequests?.count, 1)
        clock.advance(61)
        inbox.readInbox()
        await settle(inbox)
        XCTAssertNil(inbox.pullRequests, "nothing of another account, not even the last copy")
        XCTAssertEqual(inbox.inboxHold, .wrongAccount)
    }

    func testAnOldSnapshotIsRefused() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)], updatedAt: clock.now.timeIntervalSince1970 - 3600))
        do { _ = try await client()!.inbox(); XCTFail() } catch { XCTAssertEqual(error as? RelayInboxFailure, .invalidResponse) }
    }

    // MARK: What is sent, and where

    func testEveryRequestGoesToTheAuthorityWithThisMacsRelayTokenOnly() async throws {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]))
        await relay.answer("POST /inbox", snapshot([pullRequest(1)]))
        await relay.answer("GET /inbox/notifications", notes(["7"]))
        await relay.answer("POST /inbox/notifications", notes([]))
        await relay.answer("DELETE /inbox", RelayHTTPReply(status: 204, data: Data()))
        let client = client()!
        _ = try await client.inbox()
        _ = try await client.inbox(refresh: true)
        _ = try await client.notifications()
        _ = try await client.notifications(refresh: true)
        try await client.delete()
        let requests = await relay.requests
        XCTAssertEqual(requests.map(StandInRelay.key), ["GET /inbox", "POST /inbox", "GET /inbox/notifications", "POST /inbox/notifications", "DELETE /inbox"])
        for request in requests {
            XCTAssertEqual(request.url?.host, "access.relay.example")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer v2.device-access")
            XCTAssertNil(request.httpBody, "nothing of the user's goes up")
        }
    }

    func testTheAuthorizationPageMustBeTheRelaysOwn() async throws {
        await relay.answer("POST /inbox/authorization",
                           RelayHTTPReply(status: 200, data: Data(#"{"verification_uri":"https://auth.relay.example/inbox/authorize?id=1&code=2"}"#.utf8)))
        let url = try await client()!.authorizationURL()
        XCTAssertEqual(url.host, "auth.relay.example")
        for evil in ["https://auth.relay.example.evil.example/inbox/authorize", "http://auth.relay.example/inbox/authorize",
                     "https://auth.relay.example/enroll", "https://me@auth.relay.example/inbox/authorize"] {
            await relay.set("POST /inbox/authorization", RelayHTTPReply(status: 200, data: Data(#"{"verification_uri":"\#(evil)"}"#.utf8)))
            do { _ = try await client()!.authorizationURL(); XCTFail(evil) } catch { XCTAssertEqual(error as? RelayInboxFailure, .invalidResponse, evil) }
        }
    }

    func testTheStreamAsksForInboxWakesOnlyInServerSync() {
        let origin = URL(string: "https://relay.example")!
        XCTAssertEqual(RelayRequest.stream(origin: origin, relayToken: "v2.device-access", inbox: true)?.value(forHTTPHeaderField: "X-Relay-Inbox"), "1")
        XCTAssertNil(RelayRequest.stream(origin: origin, relayToken: "v2.device-access")?.value(forHTTPHeaderField: "X-Relay-Inbox"))
    }

    func testRetryAfterInSecondsOrAsADate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(RelayInbox.retryAfter("120", now: now), 120)
        XCTAssertEqual(RelayInbox.retryAfter("Fri, 15 Jan 2027 08:02:00 GMT", now: now), 120)
        XCTAssertNil(RelayInbox.retryAfter("soon", now: now))
    }

    // MARK: Refusals, limits, backoff: said, kept, never a loop

    func test428SaysAuthorizationIsNeededClearsWhatWasReadAndDoesNotLoop() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]), RelayHTTPReply(status: 428, data: Data()))
        await relay.answer("GET /inbox/notifications", RelayHTTPReply(status: 428, data: Data()))
        let inbox = inbox()
        inbox.readInbox()
        await settle(inbox)
        XCTAssertEqual(inbox.pullRequests?.count, 1)
        clock.advance(61)
        inbox.readInbox()
        inbox.readNotifications()
        await settle(inbox)
        XCTAssertNil(inbox.pullRequests, "nothing read under a grant that is gone")
        XCTAssertEqual(inbox.inboxHold, .authorizationRequired)
        for _ in 0..<10 { inbox.readInbox() }
        await settle(inbox)
        let asked = await relay.count("GET /inbox")
        XCTAssertEqual(asked, 2, "no request until the next check")
        XCTAssertEqual(inbox.nextRead(connected: true)?.timeIntervalSince(clock.now) ?? 0, 300, accuracy: 1)
        inbox.authorizationStarted()
        inbox.readInbox()
        await settle(inbox)
        XCTAssertLessThanOrEqual(inbox.nextRead(connected: true)?.timeIntervalSince(clock.now) ?? 999, 5, "closer while the browser is open")
    }

    func testRetryAfterIsKeptAndTheLastCopyStays() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]), RelayHTTPReply(status: 503, data: Data(), retryAfter: 600))
        let inbox = inbox()
        inbox.readInbox()
        await settle(inbox)
        clock.advance(61)
        inbox.readInbox()
        await settle(inbox)
        XCTAssertEqual(inbox.pullRequests?.count, 1, "the last copy stays, said as paused")
        guard case .paused(let until)? = inbox.inboxHold else { return XCTFail("paused") }
        XCTAssertEqual(until.timeIntervalSince(clock.now), 600, accuracy: 1)
        clock.advance(599)
        inbox.readInbox()
        inbox.readDue(connected: false)
        await settle(inbox)
        var asked = await relay.count("GET /inbox")
        XCTAssertEqual(asked, 2)
        clock.advance(2)
        inbox.readInbox()
        await settle(inbox)
        asked = await relay.count("GET /inbox")
        XCTAssertEqual(asked, 3)
    }

    func testTooManyRequestsWaitsTooAndRefreshIsTheOnlyWayPast() async {
        await relay.answer("GET /inbox", RelayHTTPReply(status: 429, data: Data(), retryAfter: 45))
        let inbox = inbox()
        inbox.readInbox()
        await settle(inbox)
        XCTAssertEqual(inbox.inboxHold, .paused(until: clock.now.addingTimeInterval(45)))
        inbox.readInbox()
        await settle(inbox)
        let asked = await relay.count("GET /inbox")
        XCTAssertEqual(asked, 1)
    }

    func testWithoutRetryAfterTheBackoffIsBounded() {
        var pacer = RelayReadPacer()
        let now = Date(timeIntervalSince1970: 0)
        let waits = (0..<8).map { _ in pacer.failed(.invalidResponse, now: now).timeIntervalSince(now) }
        XCTAssertEqual(waits, [30, 60, 120, 240, 480, 900, 900, 900])
        pacer.failed(.unavailable(until: now), now: now)
        XCTAssertEqual(pacer.notBefore.timeIntervalSince(now), 5, "never zero")
    }

    func testRepeated503sWithoutRetryAfterAndNetworkFailuresBackOffFurther() async {
        await relay.answer("GET /inbox", RelayHTTPReply(status: 503, data: Data()))
        let inbox = inbox()
        var waits: [TimeInterval] = []
        for _ in 0..<4 {
            inbox.readInbox()
            await settle(inbox)
            waits.append(inbox.inbox.notBefore.timeIntervalSince(clock.now))
            clock.advance(waits.last! + 1)
        }
        XCTAssertEqual(waits, [30, 60, 120, 240], "without Retry-After, the backoff grows")
        guard case .paused(let until)? = inbox.inboxHold else { return XCTFail("paused") }
        XCTAssertEqual(until, inbox.inbox.notBefore)

        let offline = RelayInboxAccess(authority: URL(string: "https://access.relay.example")!, browser: URL(string: "https://auth.relay.example")!,
                                       token: "v2.device-access", subject: "10", send: { _ in throw URLError(.notConnectedToInternet) })
        let clock = clock
        let network = GitHubServerInbox(client: { var client = RelayInboxClient(access: offline); client.now = { clock.now }; return client },
                                        now: { clock.now })
        waits = []
        for _ in 0..<3 {
            network.readInbox()
            await settle(network)
            waits.append(network.inbox.notBefore.timeIntervalSince(clock.now))
            clock.advance(waits.last! + 1)
        }
        XCTAssertEqual(waits, [30, 60, 120])
    }

    func testAMacThatLostItsAccessForgetsTheReadsItWasAskedFor() async {
        await relay.answer("POST /inbox", snapshot([pullRequest(1)]))
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]))
        await relay.hold("GET /inbox")
        let inbox = inbox()
        inbox.readInbox()
        await Task.yield()
        inbox.readInbox(refresh: true)
        subject = "11"
        await relay.release("GET /inbox")
        try? await Task.sleep(for: .milliseconds(20))
        await settle(inbox)
        XCTAssertEqual(inbox.inboxHold, .macNotReady)
        subject = "10"
        inbox.readInbox()
        await settle(inbox)
        let refreshes = await relay.count("POST /inbox")
        let reads = await relay.count("GET /inbox")
        XCTAssertEqual(refreshes, 0, "no stale refresh spends the relay's budget")
        XCTAssertEqual(reads, 2)
    }

    func test401AsksThisMacsAccessToRenew() async {
        await relay.answer("GET /inbox", RelayHTTPReply(status: 401, data: Data()))
        let inbox = inbox()
        var renewals = 0
        inbox.onDeviceExpired = { renewals += 1 }
        inbox.readInbox()
        await settle(inbox)
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(inbox.inboxHold, .deviceExpired)
    }

    func testANetworkFailureIsAPauseNotAnEmptyInbox() async {
        let failing = RelayInboxAccess(authority: URL(string: "https://access.relay.example")!, browser: URL(string: "https://auth.relay.example")!,
                                       token: "v2.device-access", subject: "10", send: { _ in throw URLError(.notConnectedToInternet) })
        let clock = clock
        let inbox = GitHubServerInbox(client: { var client = RelayInboxClient(access: failing); client.now = { clock.now }; return client },
                                      now: { clock.now })
        inbox.readInbox()
        await settle(inbox)
        XCTAssertNil(inbox.pullRequests)
        XCTAssertEqual(inbox.inboxHold, .paused(until: clock.now.addingTimeInterval(30)))
    }

    func testWithoutAVerifiedMacNothingIsAskedAndItSaysSo() async {
        ready = false
        let inbox = inbox()
        inbox.readInbox()
        inbox.readNotifications()
        await settle(inbox)
        let asked = await relay.requests.count
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(inbox.hold, .macNotReady)
        XCTAssertNil(inbox.nextRead(connected: false))
    }

    // MARK: Bursts and late answers

    func testWakesDuringAReadBecomeOneMoreRead() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]), snapshot([pullRequest(1), pullRequest(2)]))
        await relay.hold("GET /inbox")
        let inbox = inbox()
        inbox.readInbox()
        await Task.yield()
        for _ in 0..<20 { inbox.readInbox() }
        await relay.release("GET /inbox")
        await settle(inbox)
        let asked = await relay.count("GET /inbox")
        XCTAssertEqual(asked, 2, "a burst of wakes is one more read, and the last one is not lost")
        XCTAssertEqual(inbox.pullRequests?.count, 2)
    }

    func testAnAnswerAfterSignOutIsDropped() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]))
        await relay.hold("GET /inbox")
        let inbox = inbox()
        inbox.readInbox()
        await Task.yield()
        inbox.reset()
        await relay.release("GET /inbox")
        await settle(inbox)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(inbox.pullRequests)
        XCTAssertNil(inbox.lastInboxRead)
    }

    func testAnAnswerAfterAnAccountChangeIsDropped() async {
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]))
        await relay.hold("GET /inbox")
        let inbox = inbox()
        inbox.readInbox()
        await Task.yield()
        subject = "11"
        await relay.release("GET /inbox")
        try? await Task.sleep(for: .milliseconds(20))
        await settle(inbox)
        XCTAssertNil(inbox.pullRequests)
        XCTAssertEqual(inbox.inboxHold, .macNotReady)
    }

    // MARK: Notifications

    func testNotificationsAreReadAtTheRelaysPace() async {
        await relay.answer("GET /inbox/notifications", notes(["7", "8"], pollInterval: 60))
        let inbox = inbox()
        inbox.readNotifications()
        await settle(inbox)
        XCTAssertEqual(inbox.notifications?.map(\.id), ["7", "8"])
        clock.advance(30)
        inbox.readDue(connected: true)
        await settle(inbox)
        var asked = await relay.count("GET /inbox/notifications")
        XCTAssertEqual(asked, 1)
        clock.advance(31)
        inbox.readDue(connected: true)
        await settle(inbox)
        asked = await relay.count("GET /inbox/notifications")
        XCTAssertEqual(asked, 2)
    }

    func testMarkedReadShowsAtOnceThenTheRelayRereadsForTheOtherMacs() async {
        await relay.answer("GET /inbox/notifications", notes(["7"]))
        await relay.answer("POST /inbox/notifications", notes([]))
        let inbox = inbox()
        inbox.readNotifications()
        await settle(inbox)
        inbox.markedRead("7")
        XCTAssertEqual(inbox.notifications?.first?.unread, false)
        await settle(inbox)
        let refreshed = await relay.count("POST /inbox/notifications")
        XCTAssertEqual(refreshed, 1)
        XCTAssertEqual(inbox.notifications?.count, 0)
    }

    func testSeveralMarkedReadAtOnceAskTheRelayOnce() async {
        await relay.answer("GET /inbox/notifications", notes(["7", "8", "9"]))
        await relay.answer("POST /inbox/notifications", notes(["9"]))
        let inbox = inbox()
        inbox.readNotifications()
        await settle(inbox)
        inbox.markedRead(["7", "8"])
        XCTAssertEqual(inbox.notifications?.filter(\.unread).map(\.id), ["9"])
        await settle(inbox)
        let refreshed = await relay.count("POST /inbox/notifications")
        XCTAssertEqual(refreshed, 1)
    }

    func testMoreUnreadThanTheRelayKeepsIsSaid() async {
        await relay.answer("GET /inbox/notifications", notes(["7"], complete: false))
        let inbox = inbox()
        inbox.readNotifications()
        await settle(inbox)
        XCTAssertFalse(inbox.notificationsComplete)
    }

    func testAPausedNotificationReadDoesNotStopPullRequests() async {
        await relay.answer("GET /inbox/notifications", RelayHTTPReply(status: 503, data: Data(), retryAfter: 3600))
        await relay.answer("GET /inbox", snapshot([pullRequest(1)]))
        let inbox = inbox()
        inbox.readNotifications()
        inbox.readInbox()
        await settle(inbox)
        XCTAssertEqual(inbox.pullRequests?.count, 1)
        XCTAssertNil(inbox.inboxHold)
        XCTAssertNotNil(inbox.notificationsHold)
    }
}
