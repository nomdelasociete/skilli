import XCTest
@testable import SkilliCore

final class RelayStreamTests: XCTestCase {
    func testUnsetOriginStaysOff() {
        XCTAssertNil(RelayAddress.origin(""))
        XCTAssertNil(RelayAddress.origin("   "))
        XCTAssertNil(RelayAddress.origin("not a url"))
    }

    func testOriginBecomesStreamURL() {
        let origin = RelayAddress.origin("https://relay.example.com/stream")
        XCTAssertEqual(origin?.absoluteString, "https://relay.example.com")
        let stream = origin.map(RelayAddress.stream)
        XCTAssertEqual(stream?.absoluteString, "https://relay.example.com/stream")
    }

    func testCleartextOnlyOnThisMac() {
        XCTAssertNotNil(RelayAddress.origin("http://127.0.0.1:8080"))
        XCTAssertNil(RelayAddress.origin("http://relay.example.com"))
        XCTAssertNil(RelayAddress.origin("https://user:token@relay.example.com"))
    }

    func testGitHubTokenIsNotAStreamToken() {
        XCTAssertTrue(RelayToken.accepts("v1.abc_def-XYZ"))
        XCTAssertFalse(RelayToken.accepts("gho_userOauthToken"))
        XCTAssertFalse(RelayToken.accepts("github_pat_secret"))
        XCTAssertFalse(RelayToken.accepts("ghp_personal"))
        XCTAssertFalse(RelayToken.accepts("v1.gho_pasted"))
        XCTAssertNil(RelayRequest.stream(origin: URL(string: "https://relay.example.com")!, relayToken: "gho_userOauthToken"))
    }

    func testStreamRequestCarriesOnlyTheSealedToken() throws {
        let origin = try XCTUnwrap(RelayAddress.origin("https://relay.example.com"))
        let request = try XCTUnwrap(RelayRequest.stream(origin: origin, relayToken: "v1.sealed-token"))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer v1.sealed-token")
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(request.allHTTPHeaderFields?.values.contains { $0.contains("gho_") || $0.contains("github_pat_") } ?? false)
    }

    func testInboxPollSuspendsOnlyWhileConnected() {
        XCTAssertFalse(RelayPlan.suspendsInboxPoll(configured: false, connected: false))
        XCTAssertFalse(RelayPlan.suspendsInboxPoll(configured: false, connected: true))
        XCTAssertFalse(RelayPlan.suspendsInboxPoll(configured: true, connected: false))
        XCTAssertTrue(RelayPlan.suspendsInboxPoll(configured: true, connected: true))
        XCTAssertTrue(RelayPlan.holdsStream(configured: true, interfaceVisible: true))
        XCTAssertFalse(RelayPlan.holdsStream(configured: true, interfaceVisible: false))
        XCTAssertFalse(RelayPlan.holdsStream(configured: false, interfaceVisible: true))
    }

    func testWakesDuringAFetchBecomeOneFollowUp() {
        var coalescer = RelayCoalescer()
        XCTAssertTrue(coalescer.push(inFlight: false))
        XCTAssertFalse(coalescer.push(inFlight: true))
        XCTAssertFalse(coalescer.push(inFlight: true))
        XCTAssertTrue(coalescer.finished())
        XCTAssertFalse(coalescer.finished())
    }

    func testWakeFrameIgnoresPingAndPullRequestFields() {
        var parser = RelayFrameParser()
        XCTAssertNil(parser.consume(": connected"))
        XCTAssertNil(parser.consume(""))
        XCTAssertNil(parser.consume(": ping"))
        XCTAssertNil(parser.consume(""))
        XCTAssertNil(parser.consume("event: wake"))
        let wake = parser.consume("")
        XCTAssertNil(wake)

        let json = #"{"app":"12","installation":"34","type":"check_run","action":"completed","delivery":"abc","repo":"secret/repo","number":9,"title":"nope"}"#
        XCTAssertNil(parser.consume("event: wake"))
        XCTAssertNil(parser.consume("data: \(json)"))
        let parsed = parser.consume("")
        XCTAssertEqual(parsed, RelayWake(app: "12", installation: "34", type: "check_run", action: "completed", delivery: "abc"))
    }

    func testOtherEventsAreNotWakes() {
        XCTAssertNil(RelayWake.parse("event: ping\ndata: {}"))
        XCTAssertNil(RelayWake.parse(": connected"))
    }

    func testOnlyAnEventStreamCountsAsConnected() {
        XCTAssertTrue(RelayResponse.isEventStream("text/event-stream"))
        XCTAssertTrue(RelayResponse.isEventStream("text/event-stream; charset=utf-8"))
        XCTAssertFalse(RelayResponse.isEventStream("text/html"))
        XCTAssertFalse(RelayResponse.isEventStream(nil))
    }

    func testALiveStreamRetriesSoonAndADead200BacksOff() {
        XCTAssertEqual(RelayRetry.delay(previous: 8, established: true), 0.5)
        XCTAssertEqual(RelayRetry.delay(previous: 0, established: false), 0.5)
        XCTAssertEqual(RelayRetry.delay(previous: 0.5, established: false), 1)
        XCTAssertEqual(RelayRetry.delay(previous: 16, established: false), 30)
    }
}
