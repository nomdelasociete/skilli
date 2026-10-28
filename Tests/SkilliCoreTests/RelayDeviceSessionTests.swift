import Foundation
import XCTest
@testable import SkilliCore

private actor RelayReplies {
    var replies: [RelayHTTPReply]
    var requests: [URLRequest] = []
    var githubRequests: [URLRequest] = []
    var subject = "100"
    var nativeID: Int64 = 100
    var identityStatus = 200
    var githubStatus = 200
    func failGitHub() { githubStatus = 401 }
    var delayIdentity = false
    var identityStarted = false
    func delayIdentityResponse() { delayIdentity = true }
    func setIdentity(subject: String = "100", nativeID: Int64 = 100, status: Int = 200) {
        self.subject = subject; self.nativeID = nativeID; self.identityStatus = status
    }
    init(_ replies: [RelayHTTPReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> RelayHTTPReply {
        if request.url?.host == "api.github.com" { githubRequests.append(request); return RelayHTTPReply(status: githubStatus, data: Data("{\"id\":\(nativeID)}".utf8)) }
        if request.url?.path == "/computers/identity" {
            identityStarted = true
            if delayIdentity { try? await Task.sleep(for: .milliseconds(100)) }
            return RelayHTTPReply(status: identityStatus, data: Data("{\"subject\":\"\(subject)\"}".utf8)) }
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.networkConnectionLost) }
        return replies.removeFirst()
    }
}

@MainActor
private final class NativeToken {
    var value: String?
}

@MainActor
private final class RelayVault {
    var value: String?
    var writes = 0
    var failWrite: Int?
    init(_ value: String? = nil) { self.value = value }
    func save(_ value: String) throws {
        writes += 1
        if writes == failWrite { throw URLError(.cannotWriteToFile) }
        self.value = value
    }
}

@MainActor
final class RelayDeviceSessionTests: XCTestCase {
    private let origin = "https://relay.example"
    private func response(_ status: Int, _ json: String = "") -> RelayHTTPReply {
        RelayHTTPReply(status: status, data: Data(json.utf8))
    }
    private let grant = #"{"device_code":"one-use-code","verification_uri":"https://auth.example/enroll?code=public-code","expires_in":600}"#
    private let tokens = #"{"access_token":"v2.new","refresh_token":"refresh-new","expires_in":900,"computer_id":"computer-A","installations":["123"]}"#
    private let rotated = #"{"access_token":"v2.rotated","refresh_token":"refresh-rotated","expires_in":900,"computer_id":"computer-A"}"#

    private func existing(expires: Date = Date().addingTimeInterval(900), pending: Bool = false) throws -> String {
        let pair = try JSONDecoder().decode(RelayTokenPair.self, from: Data(tokens.utf8))
        let credentials = RelayDeviceCredentials(origin: origin, pair: pair, expiresAt: expires, requiresEnrollment: pending, authorityOrigin: "https://access.example")
        return String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self)
    }
    private func session(_ vault: RelayVault, _ server: RelayReplies,
                         browser: @escaping (URL) -> Bool = { _ in true }) -> RelayDeviceSession {
        let client = RelayDeviceSession(appID: "5332414", read: { vault.value }, save: { try vault.save($0) }, legacy: { "v1.legacy" },
            send: { try await server.send($0) }, openBrowser: browser, authorityOrigin: { "https://access.example" }, browserOrigin: { "https://auth.example" }, sleep: { _ in await Task.yield() })
        client.githubToken = { "native-test-token" }
        return client
    }
    private func assertVerified(_ client: RelayDeviceSession, token: String, origin: String) async {
        client.activate(origin: origin)
        for _ in 0..<500 {
            if client.configuration(origin: origin)?.token == token { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(client.configuration(origin: origin)?.token, token)
        client.suspend()
    }
    private func finish(_ session: RelayDeviceSession) async throws {
        for _ in 0..<1000 {
            if !session.isBusy { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Relay operation did not finish")
    }

    func testFailedEnrollmentRestartsInterruptedRestoredVerification() async throws {
        let server = RelayReplies([response(503)])
        await server.delayIdentityResponse()
        let client = session(RelayVault(try existing()), server)
        client.activate(origin: origin)
        defer { client.suspend() }
        while !(await server.identityStarted) { await Task.yield() }
        client.enroll(origin: origin)
        try await finish(client)
        for _ in 0..<500 {
            if client.configuration(origin: origin)?.token == "v2.new" { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
    }

    func testIdentityRequestSetsGitHubUserAgent() async throws {
        let server = RelayReplies([])
        let client = session(RelayVault(try existing()), server)
        await assertVerified(client, token: "v2.new", origin: origin)
        let requests = await server.githubRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "User-Agent"), "Skilli")
    }

    func testRenewalVerifiesNewTokenWithoutActivationCallback() async throws {
        let server = RelayReplies([response(200, rotated)])
        let client = session(RelayVault(try existing()), server)
        client.activate(origin: origin)
        defer { client.suspend() }
        for _ in 0..<500 {
            if client.configuration(origin: origin) != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
        client.renew()
        try await finish(client)
        for _ in 0..<500 {
            // The renewed token waits for its check: said as checking.
            if client.configuration(origin: origin) == nil { XCTAssertTrue(client.checksIdentity(origin: origin)) }
            if client.configuration(origin: origin)?.token == "v2.rotated" { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.rotated")
        XCTAssertFalse(client.checksIdentity(origin: origin))
    }

    func testFailedEnrollmentSavePreservesVerifiedConnection() async throws {
        let vault = RelayVault(try existing())
        let replacement = tokens.replacingOccurrences(of: "v2.new", with: "v2.replacement")
        let server = RelayReplies([response(201, grant), response(200, replacement)])
        let client = session(vault, server)
        client.activate(origin: origin)
        defer { client.suspend() }
        for _ in 0..<500 {
            if client.configuration(origin: origin) != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
        vault.failWrite = 1
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertEqual(client.credentials?.pair.access_token, "v2.new")
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
    }

    func testRotationReplacesInFlightIdentityCheck() async throws {
        let server = RelayReplies([response(200, rotated)])
        await server.delayIdentityResponse()
        let client = session(RelayVault(try existing()), server)
        client.activate(origin: origin)
        defer { client.suspend() }
        while !(await server.identityStarted) { await Task.yield() }
        client.renew()
        try await finish(client)
        for _ in 0..<500 {
            if client.configuration(origin: origin)?.token == "v2.rotated" { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.rotated")
    }

    func testMultipleAccountsSurviveRenewalAndRestore() async throws {
        let vault = RelayVault()
        let multiple = tokens.replacingOccurrences(of: "[\"123\"]", with: "[\"123\",\"456\"]")
        let server = RelayReplies([response(201, grant), response(200, multiple), response(200, rotated)])
        let client = session(vault, server)
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertEqual(client.installationCount, 2)
        client.renew()
        try await finish(client)
        XCTAssertEqual(client.credentials?.pair.installations, ["123", "456"])
        let restored = session(vault, RelayReplies([]))
        XCTAssertEqual(restored.installationCount, 2)
        await assertVerified(restored, token: "v2.rotated", origin: origin)
    }

    func testAPairingWithoutTheGitHubAppIsSavedAndRenews() async throws {
        let vault = RelayVault()
        let none = tokens.replacingOccurrences(of: "[\"123\"]", with: "[]")
        let server = RelayReplies([response(201, grant), response(200, none), response(200, rotated)])
        let client = session(vault, server)
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertEqual(client.installationCount, 0)
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
        XCTAssertEqual(client.message, "This Mac is paired without live updates. Install the GitHub App, then Add Accounts…, for instant updates.")
        client.renew()
        try await finish(client)
        XCTAssertEqual(client.credentials?.pair.installations, [])
        let restored = session(vault, RelayReplies([]))
        XCTAssertEqual(restored.installationCount, 0)
        await assertVerified(restored, token: "v2.rotated", origin: origin)
        XCTAssertEqual(restored.message, "GitHub account verified. No account for live updates.")
    }

    func testANonNumericInstallationIsStillRefused() async throws {
        let vault = RelayVault()
        let invalid = tokens.replacingOccurrences(of: "[\"123\"]", with: "[\"abc\"]")
        let client = session(vault, RelayReplies([response(201, grant), response(200, invalid)]))
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertNil(vault.value)
        XCTAssertNil(client.configuration(origin: origin))
    }

    func testUnavailableEnrollmentPreservesLegacyAndNeverOpensBrowser() async throws {
        for status in [404, 503, 429] {
            let vault = RelayVault()
            let server = RelayReplies([response(status)])
            var opened = false
            let client = session(vault, server, browser: { _ in opened = true; return true })
            client.enroll(origin: origin)
            try await finish(client)
            XCTAssertFalse(opened)
            XCTAssertNil(vault.value)
            XCTAssertNil(client.configuration(origin: origin))
            let requests = await server.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0].url?.path, "/devices")
            XCTAssertEqual(requests[0].url?.host, "access.example")
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: XCTUnwrap(requests[0].httpBody)), ["app":"5332414"])
            XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testBrowserEnrollmentPollsPendingThenAtomicallyStoresBothTokens() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant), response(202), response(200, tokens)])
        var opened: URL?
        let client = session(vault, server, browser: { opened = $0; return true })
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertEqual(opened?.host, "auth.example")
        XCTAssertEqual(vault.writes, 1)
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
        XCTAssertEqual(client.credentials?.pair.refresh_token, "refresh-new")
        XCTAssertEqual(client.credentials?.pair.computer_id, "computer-A")
        XCTAssertEqual(client.credentials?.pair.installations, ["123"])
        let requests = await server.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/devices", "/devices/token", "/devices/token"])
        for request in requests.dropFirst() {
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody)), ["device_code": "one-use-code"])
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testRefusedCodeStopsPollingWithoutReplacingLegacy() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant), response(401)])
        let client = session(vault, server)
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertNil(vault.value)
        XCTAssertNil(client.configuration(origin: origin))
        let count = await server.requests.count
        XCTAssertEqual(count, 2)
    }

    func testInvalidBrowserURLIsNotOpened() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant.replacingOccurrences(of: "https://auth", with: "http://auth"))])
        var opened = false
        let client = session(vault, server, browser: { _ in opened = true; return true })
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertFalse(opened)
        XCTAssertNil(vault.value)
    }


    func testUntrustedHTTPSBrowserOriginIsNeverOpened() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant.replacingOccurrences(of: "auth.example", with: "attacker.example"))])
        var opened = false
        let client = session(vault, server, browser: { _ in opened = true; return true })
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertFalse(opened)
        XCTAssertNil(vault.value)
    }

    func testTransientKeychainFailureRecoversWithoutRelaunch() async throws {
        let stored = try existing()
        var locked = true
        let client = RelayDeviceSession(appID: "5332414", read: {
            if locked { throw URLError(.cannotOpenFile) }
            return stored
        }, save: { _ in }, legacy: { "v1.legacy" }, send: { request in
                RelayHTTPReply(status: 200, data: Data((request.url?.host == "api.github.com" ? #"{"id":100}"# : #"{"subject":"100"}"#).utf8))
            }, openBrowser: { _ in true },
            authorityOrigin: { "https://access.example" }, browserOrigin: { "https://auth.example" })
        XCTAssertNil(client.configuration(origin: origin))
        client.githubToken = { "native-test-token" }
        locked = false
        client.activate(origin: origin)
        await assertVerified(client, token: "v2.new", origin: origin)
        client.suspend()
    }

    func testInvalidRevocationCredentialDoesNotBlockEnrollment() async throws {
        let vault = RelayVault(try existing())
        let server = RelayReplies([response(401), response(201, grant), response(200, tokens)])
        let client = session(vault, server)
        client.revoke()
        try await finish(client)
        XCTAssertNil(client.credentials?.pendingRevocation)
        XCTAssertNil(client.configuration(origin: origin))
        client.enroll(origin: origin)
        try await finish(client)
        await assertVerified(client, token: "v2.new", origin: origin)
        let count = await server.requests.count
        XCTAssertEqual(count, 3)
    }

    func testShortLivedAccessDoesNotScheduleImmediateRotationLoop() async throws {
        var saved = try JSONDecoder().decode(RelayDeviceCredentials.self, from: Data(existing().utf8))
        saved.pair = RelayTokenPair(access_token: "v2.short", refresh_token: "refresh-short", expires_in: 1, computer_id: "computer-A")
        saved.expiresAt = Date().addingTimeInterval(1)
        let vault = RelayVault(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self))
        let server = RelayReplies([response(200, tokens)])
        let client = session(vault, server)
        client.activate(origin: origin)
        try await Task.sleep(for: .milliseconds(100))
        client.suspend()
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
    }

    func testRejectedAccessCannotReconnectOrBypassRenewalBackoff() async throws {
        let vault = RelayVault(try existing())
        let server = RelayReplies([response(503)])
        let client = session(vault, server)
        client.onChange = { XCTAssertNil(client.configuration(origin: self.origin)) }
        client.accessExpired()
        try await finish(client)
        for _ in 0..<10 { client.accessExpired(); client.renew() }
        try await finish(client)
        let count = await server.requests.count
        XCTAssertEqual(count, 1)
        XCTAssertNil(client.configuration(origin: origin))
        let restored = session(vault, server)
        XCTAssertNil(restored.configuration(origin: origin), "A pending rotation must not revive rejected access")
        client.onChange = nil
        client.suspend()
    }

    func testRejectedAccessStaysBlockedWhenRetryMarkerCannotBeSaved() async throws {
        let vault = RelayVault(try existing())
        vault.failWrite = 1
        let server = RelayReplies([response(200, rotated)])
        let client = session(vault, server)
        client.accessExpired()
        try await finish(client)
        client.accessExpired()
        try await finish(client)
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
        XCTAssertNil(client.configuration(origin: origin))
    }

    func testConcurrentRenewalTriggersOnlyOneRotationAndPreservesInstallations() async throws {
        let vault = RelayVault(try existing())
        let server = RelayReplies([response(200, rotated)])
        let client = session(vault, server)
        client.renew()
        client.renew()
        client.accessExpired()
        try await finish(client)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/tokens/refresh")
        XCTAssertEqual(requests[0].url?.host, "access.example")
        let payload = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(requests[0].httpBody))
        XCTAssertEqual(payload["refresh_token"], "refresh-new")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(payload["request_id"])))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(client.credentials?.pair.installations, ["123"])
        await assertVerified(client, token: "v2.rotated", origin: origin)
        let restored = session(vault, server)
        XCTAssertEqual(restored.credentials?.pair.refresh_token, "refresh-rotated")
        XCTAssertEqual(vault.writes, 2) // marker then complete new pair
    }

    func testLostRotationResponseRetriesSameRequestAfterRestart() async throws {
        let vault = RelayVault(try existing())
        let lost = RelayReplies([])
        let client = session(vault, lost)
        client.renew()
        try await finish(client)
        XCTAssertFalse(client.needsEnrollment)
        let server = RelayReplies([response(200, rotated)])
        let restored = session(vault, server)
        restored.renew()
        try await finish(restored)
        let first = await lost.requests
        let retried = await server.requests
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(retried.count, 1)
        let initialBody = try JSONDecoder().decode([String:String].self, from: XCTUnwrap(first[0].httpBody))
        let retryBody = try JSONDecoder().decode([String:String].self, from: XCTUnwrap(retried[0].httpBody))
        XCTAssertEqual(initialBody, retryBody)
        await assertVerified(restored, token: "v2.rotated", origin: origin)
    }

    func testRefusedRefreshRequiresEnrollmentAndDoesNotRetry() async throws {
        let vault = RelayVault(try existing())
        let server = RelayReplies([response(401)])
        let client = session(vault, server)
        client.accessExpired()
        try await finish(client)
        client.accessExpired()
        XCTAssertTrue(client.needsEnrollment)
        XCTAssertNil(client.configuration(origin: origin))
        let count = await server.requests.count
        XCTAssertEqual(count, 1)
    }

    func testFailedMarkerWriteDoesNotSendRefreshToken() async throws {
        let vault = RelayVault(try existing())
        vault.failWrite = 1
        let server = RelayReplies([response(200, rotated)])
        let client = session(vault, server)
        client.renew()
        try await finish(client)
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
        await assertVerified(client, token: "v2.new", origin: origin)
    }

    func testFailedPairWritePreservesSameRotationForRetry() async throws {
        let vault = RelayVault(try existing())
        vault.failWrite = 2
        let server = RelayReplies([response(200, rotated), response(200, rotated)])
        let client = session(vault, server)
        client.renew()
        try await finish(client)
        let restored = session(vault, server)
        XCTAssertFalse(restored.needsEnrollment)
        restored.renew()
        try await finish(restored)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 2)
        let first = try JSONDecoder().decode([String:String].self, from: XCTUnwrap(requests[0].httpBody))
        let second = try JSONDecoder().decode([String:String].self, from: XCTUnwrap(requests[1].httpBody))
        XCTAssertEqual(first, second)
        await assertVerified(restored, token: "v2.rotated", origin: origin)
    }

    func testCredentialsAreBoundToOrigin() async throws {
        let client = session(RelayVault(try existing()), RelayReplies([]))
        XCTAssertNil(client.configuration(origin: "https://other.example"))
        await assertVerified(client, token: "v2.new", origin: origin + "/")
    }

    func testRevocationUsesRefreshCredentialAndKeepsRevokedMarker() async throws {
        let vault = RelayVault(try existing())
        let server = RelayReplies([response(204)])
        let client = session(vault, server)
        client.revoke()
        try await finish(client)
        let requests = await server.requests
        XCTAssertEqual(requests[0].url?.path, "/computers/revoke")
        XCTAssertEqual(requests[0].url?.host, "access.example")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(requests[0].httpBody)
        XCTAssertTrue(session(vault, server).needsEnrollment)
        XCTAssertNil(client.configuration(origin: origin))
    }

    func testRevocationWorksWithoutRenewingExpiredAccess() async throws {
        let vault = RelayVault(try existing(expires: Date().addingTimeInterval(-1)))
        let server = RelayReplies([response(204)])
        let client = session(vault, server)
        client.revoke()
        try await finish(client)
        let requests = await server.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/computers/revoke"])
    }

    func testPendingRevocationSurvivesRestart() async throws {
        let vault = RelayVault(try existing())
        let server = RelayReplies([response(503), response(204)])
        let first = session(vault, server)
        first.revoke()
        try await finish(first)
        XCTAssertEqual(first.credentials?.pendingRevocation, true)
        XCTAssertNil(first.configuration(origin: origin))
        let restarted = session(vault, server)
        restarted.revoke()
        try await finish(restarted)
        XCTAssertNil(restarted.credentials?.pendingRevocation)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
    }

    func testLegacyExpirationDoesNotAttemptRefreshOrRevocation() async throws {
        let vault = RelayVault()
        let server = RelayReplies([])
        let client = session(vault, server)
        client.accessExpired()
        client.revoke()
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertNil(vault.value)
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
    }

    func testSuspendDoesNotEraseEnrollment() throws {
        let vault = RelayVault(try existing())
        let client = session(vault, RelayReplies([]))
        client.activate(origin: origin)
        client.suspend()
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertEqual(vault.writes, 0)
    }

    func testExpiredAccessRenewsAutomaticallyOnActivation() async throws {
        let vault = RelayVault(try existing(expires: Date().addingTimeInterval(-1)))
        let server = RelayReplies([response(200, rotated)])
        let client = session(vault, server)
        client.activate(origin: origin)
        for _ in 0..<1000 {
            if client.credentials?.pair.access_token == "v2.rotated" { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        client.suspend()
        XCTAssertNil(client.configuration(origin: origin))
        let count = await server.requests.count
        XCTAssertEqual(count, 1)
    }

    func testSuspendingAnExpiredSessionPreventsScheduledRenewal() async throws {
        let vault = RelayVault(try existing(expires: Date().addingTimeInterval(-1)))
        let server = RelayReplies([response(200, rotated)])
        let client = session(vault, server)
        client.activate(origin: origin)
        client.suspend()
        try await Task.sleep(for: .milliseconds(10))
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
    }

    func testEnrollmentWriteFailurePreservesLegacy() async throws {
        let vault = RelayVault()
        vault.failWrite = 1
        let server = RelayReplies([response(201, grant), response(200, tokens)])
        let client = session(vault, server)
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertNil(vault.value)
        XCTAssertNil(client.configuration(origin: origin))
    }

    func testCancellationBeforeSetupDoesNotMakeNetworkRequest() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant)])
        let client = session(vault, server)
        client.enroll(origin: origin)
        client.cancelEnrollment()
        try await finish(client)
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
        XCTAssertNil(client.configuration(origin: origin))
    }

    func testUnreadableSavedEnrollmentDoesNotFallBackToLegacy() {
        let client = session(RelayVault("invalid saved record"), RelayReplies([]))
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertTrue(client.needsEnrollment)
    }
    func testBrowserAccountMismatchCannotInstallEnrollment() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant), response(200, tokens)])
        await server.setIdentity(subject: "200")
        let client = session(vault, server)
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertNil(vault.value)
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertTrue(client.message?.contains("different GitHub account") == true)
    }

    func testRestoredPairingIsBlockedUntilIdentityMatchesAndAfterAccountSwitch() async throws {
        let server = RelayReplies([])
        let client = session(RelayVault(try existing()), server)
        var nativeToken: String? = "alice"
        client.githubToken = { nativeToken }
        XCTAssertNil(client.configuration(origin: origin))
        client.activate(origin: origin)
        for _ in 0..<500 {
            if client.configuration(origin: origin) != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertNotNil(client.configuration(origin: origin))
        nativeToken = "bob"
        XCTAssertNil(client.configuration(origin: origin), "Account replacement must stop access synchronously")
        await server.setIdentity(nativeID: 200)
        client.activate(origin: origin)
        for _ in 0..<500 {
            if client.message?.contains("different GitHub account") == true { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertTrue(client.message?.contains("different GitHub account") == true)
        nativeToken = nil
        XCTAssertNil(client.configuration(origin: origin))
        client.suspend()
    }

    func testARestoredPairingChecksItsIdentityUntilVerified() async throws {
        let server = RelayReplies([])
        let client = session(RelayVault(try existing()), server)
        var nativeToken = "alice"
        client.githubToken = { nativeToken }
        XCTAssertTrue(client.checksIdentity(origin: origin), "Not verified yet, not failed: checking")
        XCTAssertFalse(client.checksIdentity(origin: "https://other-relay.example"), "Saved for another relay: not this one's check")
        client.activate(origin: origin)
        for _ in 0..<500 {
            if client.configuration(origin: origin) != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertNotNil(client.configuration(origin: origin))
        XCTAssertFalse(client.checksIdentity(origin: origin))
        nativeToken = "alice-again"
        XCTAssertTrue(client.checksIdentity(origin: origin), "Another GitHub sign-in is checked again")
        nativeToken = "alice"
        client.suspend()
        XCTAssertTrue(client.checksIdentity(origin: origin), "Each activation checks again")
    }

    func testAFailedIdentityCheckIsNoLongerChecking() async throws {
        let server = RelayReplies([])
        await server.setIdentity(status: 503)
        let client = session(RelayVault(try existing()), server)
        client.githubToken = { "alice" }
        client.activate(origin: origin)
        for _ in 0..<500 {
            if !client.checksIdentity(origin: origin) { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertFalse(client.checksIdentity(origin: origin))
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertTrue(client.message?.contains("Could not verify") == true)
        // Tried again (Settings shown again): checking at once, said.
        var changes = 0
        client.onChange = { changes += 1 }
        await server.setIdentity()
        client.activate(origin: origin)
        XCTAssertTrue(client.checksIdentity(origin: origin))
        XCTAssertGreaterThan(changes, 0)
        for _ in 0..<500 {
            if client.configuration(origin: origin) != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertNotNil(client.configuration(origin: origin))
        XCTAssertFalse(client.checksIdentity(origin: origin))
        client.suspend()
    }

    func testUnavailableIdentityEndpointFailsClosed() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant), response(200, tokens)])
        await server.setIdentity(status: 503)
        let client = session(vault, server)
        client.enroll(origin: origin)
        try await finish(client)
        XCTAssertNil(vault.value)
        XCTAssertNil(client.configuration(origin: origin))
    }

    func testLateIdentityResponseCannotRestoreSignedOutSession() async throws {
        let server = RelayReplies([])
        await server.delayIdentityResponse()
        let client = session(RelayVault(try existing()), server)
        var token: String? = "alice"
        client.githubToken = { token }
        client.activate(origin: origin)
        for _ in 0..<500 {
            if await server.identityStarted { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let started = await server.identityStarted
        XCTAssertTrue(started)
        token = nil
        client.suspend()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(client.configuration(origin: origin))
    }

    // MARK: Single sign-in (docs/github-single-sign-in.md)

    private let chainedGrant = #"{"device_code":"one-use-code","verification_uri":"https://auth.example/enroll?code=public-code&app=5332414","expires_in":600,"chain":["inbox","user_code","subject"]}"#

    /// Signing in and enrolling together: no native token until the user
    /// typed the code on GitHub, the tab's last page.
    private func signingIn(_ vault: RelayVault, _ server: RelayReplies, native: NativeToken,
                           browser: @escaping (URL) -> Bool = { _ in true }) -> RelayDeviceSession {
        let client = session(vault, server, browser: browser)
        client.githubToken = { native.value }
        return client
    }
    private func query(_ url: URL?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testSignInChainOpensOneTabThenSavesOnlyAfterTheNativeTokenMatches() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, chainedGrant), response(200, tokens)])
        let native = NativeToken()
        var opened: [URL] = []
        var elsewhere = 0
        var paired: [Bool] = []
        let client = signingIn(vault, server, native: native, browser: { opened.append($0); return true })
        XCTAssertTrue(client.enroll(origin: origin, chain: RelaySignInChain(inbox: true, userCode: "ABCD-1234"),
                                    codeNotShown: { elsewhere += 1 }, paired: { paired.append($0) }))
        for _ in 0..<1000 where client.message?.hasPrefix("Last step") != true { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(client.message, "Last step: enter the code on GitHub. skil.li finishes by itself.")
        XCTAssertNil(vault.value, "nothing is saved before this Mac's own token is compared")
        let githubBefore = await server.githubRequests.count
        XCTAssertEqual(githubBefore, 0)
        let pairArrived = Date()

        try await Task.sleep(for: .milliseconds(50))
        native.value = "native-test-token"
        try await finish(client)
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.host, "auth.example")
        XCTAssertEqual(opened.first?.path, "/enroll")
        XCTAssertEqual(query(opened.first), ["code": "public-code", "app": "5332414", "inbox": "1", "user_code": "ABCD-1234"])
        let requests = await server.requests
        XCTAssertEqual(requests.map { "\($0.httpMethod!) \($0.url!.absoluteString)" },
                       ["POST https://access.example/devices", "POST https://access.example/devices/token"])
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: XCTUnwrap(requests[0].httpBody)), ["app": "5332414"])
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: XCTUnwrap(requests[1].httpBody)), ["device_code": "one-use-code"])
        let github = await server.githubRequests
        XCTAssertEqual(github.map { $0.url!.absoluteString }, ["https://api.github.com/user"])
        XCTAssertEqual(github.first?.value(forHTTPHeaderField: "Authorization"), "Bearer native-test-token")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && !String(decoding: $0.httpBody ?? Data(), as: UTF8.self).contains("native-test-token") },
                      "the native token goes to GitHub only")
        let identity = await server.identityStarted
        XCTAssertTrue(identity)
        XCTAssertEqual(vault.writes, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(client.credentials?.expiresAt), pairArrived.addingTimeInterval(900),
                                 "the access token's life counts from its arrival, not from the save")
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
        XCTAssertEqual(client.verifiedSubject, "100")
        XCTAssertEqual(paired, [true])
        XCTAssertEqual(elsewhere, 0, "the relay's tab showed the code")
    }

    func testSignInChainWithAnotherGitHubAccountSavesNothing() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, chainedGrant), response(200, tokens)])
        await server.setIdentity(subject: "100", nativeID: 200)
        let native = NativeToken()
        var paired: [Bool] = []
        let client = signingIn(vault, server, native: native)
        client.enroll(origin: origin, chain: RelaySignInChain(inbox: true, userCode: "ABCD-1234"), paired: { paired.append($0) })
        for _ in 0..<1000 where client.message?.hasPrefix("Last step") != true { try await Task.sleep(for: .milliseconds(1)) }
        native.value = "native-test-token"
        try await finish(client)
        XCTAssertNil(vault.value)
        XCTAssertNil(client.configuration(origin: origin))
        XCTAssertEqual(paired, [])
        XCTAssertEqual(client.message, "Live updates use a different GitHub account. Authorize this Mac again using the same account as the app.")
    }

    func testOlderRelayGetsAPlainURLAndTheCodeOpensElsewhereWhenThePairingArrives() async throws {
        let vault = RelayVault()
        let server = RelayReplies([response(201, grant), response(200, tokens)])
        let native = NativeToken()
        var opened: [URL] = []
        var elsewhere = 0
        var paired: [Bool] = []
        let client = signingIn(vault, server, native: native, browser: { opened.append($0); return true })
        client.enroll(origin: origin, chain: RelaySignInChain(inbox: true, userCode: "ABCD-1234"),
                      codeNotShown: { elsewhere += 1 }, paired: { paired.append($0) })
        for _ in 0..<1000 where client.message?.hasPrefix("Last step") != true { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(elsewhere, 1, "GitHub's device page opens once the pairing arrives")
        XCTAssertEqual(query(opened.first), ["code": "public-code"])
        native.value = "native-test-token"
        try await finish(client)
        XCTAssertEqual(elsewhere, 1)
        XCTAssertEqual(paired, [false], "no inbox grant was chained")
        XCTAssertEqual(client.configuration(origin: origin)?.token, "v2.new")
    }

    func testUnavailableEnrollmentHandsTheCodeBackOnce() async throws {
        let server = RelayReplies([response(503)])
        var opened = 0
        var elsewhere = 0
        let client = signingIn(RelayVault(), server, native: NativeToken(), browser: { _ in opened += 1; return true })
        XCTAssertTrue(client.enroll(origin: origin, chain: RelaySignInChain(inbox: true, userCode: "ABCD-1234"), codeNotShown: { elsewhere += 1 }))
        try await finish(client)
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(elsewhere, 1)
    }

    func testRefusedChainedEnrollmentHandsTheCodeBack() async throws {
        let server = RelayReplies([response(201, chainedGrant), response(401)])
        var elsewhere = 0
        let client = signingIn(RelayVault(), server, native: NativeToken())
        client.enroll(origin: origin, chain: RelaySignInChain(inbox: false, userCode: "ABCD-1234"), codeNotShown: { elsewhere += 1 })
        try await finish(client)
        XCTAssertEqual(elsewhere, 1, "cancelled in the tab: the Mac still signs in")
    }

    func testNothingStartsWithoutANativeTokenOrAWellFormedCode() async throws {
        let server = RelayReplies([response(201, chainedGrant)])
        let client = signingIn(RelayVault(), server, native: NativeToken())
        XCTAssertFalse(client.enroll(origin: origin))
        XCTAssertFalse(client.enroll(origin: origin, chain: RelaySignInChain(inbox: true, userCode: "abcd-1234")))
        XCTAssertFalse(client.enroll(origin: origin, chain: RelaySignInChain(inbox: true, userCode: "ABCD-1234&inbox=1")))
        XCTAssertFalse(client.isBusy)
        let count = await server.requests.count
        XCTAssertEqual(count, 0)
    }

    func testSignedInMacChainsTheInboxWithoutACode() async throws {
        let server = RelayReplies([response(201, chainedGrant), response(200, tokens)])
        var opened: URL?
        var paired: [Bool] = []
        let client = session(RelayVault(), server, browser: { opened = $0; return true })
        client.enroll(origin: origin, chain: RelaySignInChain(inbox: true), paired: { paired.append($0) })
        try await finish(client)
        XCTAssertEqual(query(opened), ["code": "public-code", "app": "5332414", "subject": "100", "inbox": "1"],
                       "the relay checks the browser's account against this Mac's before keeping a grant")
        let github = await server.githubRequests
        XCTAssertEqual(github.first?.value(forHTTPHeaderField: "Authorization"), "Bearer native-test-token")
        XCTAssertEqual(paired, [true])
    }

    func testSignedInMacAsksNoInboxGrantWhenItsGitHubIDIsUnknown() async throws {
        let server = RelayReplies([response(201, chainedGrant), response(200, tokens)])
        await server.failGitHub()
        var opened: URL?
        let client = session(RelayVault(), server, browser: { opened = $0; return true })
        client.enroll(origin: origin, chain: RelaySignInChain(inbox: true))
        try await finish(client)
        XCTAssertEqual(query(opened), ["code": "public-code", "app": "5332414"])
    }
}
