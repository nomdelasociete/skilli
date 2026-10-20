import XCTest
@testable import SkilliCore

final class MCPOAuthTests: XCTestCase {
    func testPKCEFollowsRFC7636() {
        // RFC 7636, appendix B.
        XCTAssertEqual(MCPOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = MCPOAuth.makeVerifier()
        XCTAssertEqual(verifier.count, 43)
        XCTAssertTrue(verifier.allSatisfy { $0.isLetter || $0.isNumber || "-_".contains($0) })
        XCTAssertNotEqual(verifier, MCPOAuth.makeVerifier())
    }

    func testDiscovery() {
        let header = #"Bearer error="invalid_token", error_description="No authorization provided", scope="yd.admin", resource_metadata="https://deployment.nimbus.example/api/mcp/.well-known/oauth-protected-resource""#
        let found = MCPOAuth.challenge(header)
        XCTAssertEqual(found.resourceMetadata, "https://deployment.nimbus.example/api/mcp/.well-known/oauth-protected-resource")
        XCTAssertEqual(found.scope, "yd.admin")
        XCTAssertEqual(MCPOAuth.resourceMetadataURL(for: URL(string: "https://mcp.example.com/api/mcp?x=1")!)?.absoluteString,
                       "https://mcp.example.com/.well-known/oauth-protected-resource/api/mcp")
        XCTAssertEqual(MCPOAuth.serverMetadataURLs(issuer: URL(string: "https://auth.example.com")!).first?.absoluteString,
                       "https://auth.example.com/.well-known/oauth-authorization-server")
        XCTAssertEqual(MCPOAuth.serverMetadataURLs(issuer: URL(string: "https://example.com/tenant")!).first?.absoluteString,
                       "https://example.com/.well-known/oauth-authorization-server/tenant")
    }

    func testAuthorizationURLTokensAndCallback() throws {
        let url = try XCTUnwrap(MCPOAuth.authorizationURL(endpoint: "https://auth.example.com/authorize?prompt=consent", clientID: "c 1",
                                                          redirect: "http://127.0.0.1:5000/callback", challenge: "abc", state: "s1",
                                                          scope: "yd.admin", resource: "https://mcp.example.com/mcp"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("prompt"), "consent")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "c 1")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("resource"), "https://mcp.example.com/mcp")
        XCTAssertEqual(value("scope"), "yd.admin")

        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = try XCTUnwrap(MCPOAuth.tokens(Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":3600}"#.utf8), now: now))
        XCTAssertEqual(tokens.access, "AT")
        XCTAssertEqual(tokens.refresh, "RT")
        XCTAssertEqual(tokens.expiresAt, Date(timeIntervalSince1970: 4_600))
        XCTAssertNil(MCPOAuth.tokens(Data(#"{"error":"invalid_grant"}"#.utf8)))

        let session = MCPOAuth.Session(clientID: "c", clientSecret: nil, tokenEndpoint: "t", resource: "r", scope: nil,
                                       accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(30))
        XCTAssertTrue(session.needsRefresh(now: now))
        XCTAssertFalse(session.needsRefresh(now: now.addingTimeInterval(-3_600)))

        XCTAssertEqual(String(decoding: MCPOAuth.form([("a", "x y&z"), ("b", "é")]), as: UTF8.self), "a=x%20y%26z&b=%C3%A9")
        let back = MCPOAuth.callback("/callback?code=C1&state=S1")
        XCTAssertEqual(back.code, "C1")
        XCTAssertEqual(back.state, "S1")
        XCTAssertEqual(MCPOAuth.callback("/callback?error=access_denied").error, "access_denied")
        XCTAssertTrue(MCPOAuth.isAllowed("https://x.com/mcp"))
        XCTAssertTrue(MCPOAuth.isAllowed("http://127.0.0.1:8080/mcp"))
        XCTAssertFalse(MCPOAuth.isAllowed("http://x.com/mcp"))
    }
}
