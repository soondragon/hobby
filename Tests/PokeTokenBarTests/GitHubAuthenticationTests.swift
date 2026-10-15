import XCTest
@testable import PokeTokenBar

final class GitHubAuthenticationTests: XCTestCase {
    private func response(_ json: String, status: Int = 200) -> GitHubHTTPResponse {
        GitHubHTTPResponse(status: status, data: Data(json.utf8))
    }

    func testDeviceRequestHasNoScopesOrSecretAndUsesFormEncoding() async throws {
        let transport = ProfileHTTPStub([response(#"{"device_code":"sample","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)])
        let challenge = try await GitHubAuthenticationClient(transport: transport).begin(clientID: "public-id")
        XCTAssertTrue(challenge.isValid)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "client_id=public-id")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        let encoded = GitHubAuthenticationClient.request(path: "/login/oauth/access_token", parameters: ["device_code": "a&b=c+"])
        XCTAssertEqual(String(data: encoded.httpBody!, encoding: .utf8), "device_code=a%26b%3Dc%2B")
    }

    func testPendingSlowDownThenToken() async throws {
        let transport = ProfileHTTPStub([
            response(#"{"error":"authorization_pending"}"#), response(#"{"error":"slow_down"}"#),
            response(#"{"access_token":"sample-token","token_type":"bearer","scope":"","expires_in":28800}"#)
        ])
        let client = GitHubAuthenticationClient(transport: transport)
        let pending = try await client.poll(clientID: "id", deviceCode: "device")
        let slowed = try await client.poll(clientID: "id", deviceCode: "device")
        let token = try await client.poll(clientID: "id", deviceCode: "device")
        XCTAssertEqual(pending, .pending)
        XCTAssertEqual(slowed, .slowDown)
        XCTAssertEqual(token, .authorized(token: "sample-token", expiresIn: 28800))
    }

    func testErrorsMapWithoutExposingResponseContents() async throws {
        for (code, expected) in [("access_denied", ProfileAccessError.denied), ("expired_token", .expired),
                                 ("device_flow_disabled", .notConfigured), ("incorrect_client_credentials", .notConfigured)] {
            let transport = ProfileHTTPStub([response("{\"error\":\"\(code)\",\"error_description\":\"private-detail\"}")])
            do {
                _ = try await GitHubAuthenticationClient(transport: transport).poll(clientID: "id", deviceCode: "device")
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? ProfileAccessError, expected) }
        }
    }

    func testRejectsElevatedScopesAndMalformedToken() async throws {
        for json in [#"{"access_token":"token","token_type":"bearer","scope":"repo"}"#,
                     #"{"access_token":"token\r\nother","token_type":"bearer","scope":""}"#,
                     #"{"access_token":"token","token_type":"other","scope":""}"#,
                     #"{"access_token":"token","token_type":"bearer","scope":"","expires_in":0}"#] {
            let transport = ProfileHTTPStub([response(json)])
            do {
                _ = try await GitHubAuthenticationClient(transport: transport).poll(clientID: "id", deviceCode: "device")
                XCTFail("Expected invalid token")
            } catch { XCTAssertEqual(error as? ProfileAccessError, .invalidResponse) }
        }
    }

    func testRejectsUntrustedVerificationURLAndRateLimit() async throws {
        let transport = ProfileHTTPStub([response(#"{"device_code":"sample","user_code":"ABCD-1234","verification_uri":"https://example.com/login/device","expires_in":900,"interval":5}"#)])
        do { _ = try await GitHubAuthenticationClient(transport: transport).begin(clientID: "id"); XCTFail() }
        catch { XCTAssertEqual(error as? ProfileAccessError, .invalidResponse) }
        let rateLimited = ProfileHTTPStub([response("{}", status: 429)])
        do { _ = try await GitHubAuthenticationClient(transport: rateLimited).begin(clientID: "id"); XCTFail() }
        catch { XCTAssertEqual(error as? ProfileAccessError, .rateLimited) }
    }

    func testProfileUsesAuthenticatedUserAndValidatesIdentity() async throws {
        let transport = ProfileHTTPStub([response(#"{"id":42,"login":"sample-trainer","name":null}"#)])
        let profile = try await GitHubProfileClient(transport: transport).profile(accessToken: "sample-token")
        XCTAssertEqual(profile.alias, "@sample-trainer")
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sample-token")
        let invalid = ProfileHTTPStub([response(#"{"id":0,"login":"invalid/login","name":null}"#)])
        do { _ = try await GitHubProfileClient(transport: invalid).profile(accessToken: "sample-token"); XCTFail() }
        catch { XCTAssertEqual(error as? ProfileAccessError, .invalidResponse) }
    }

    func testConfigurationAllowsOverrideAndRejectsSecretLikeInput() {
        XCTAssertTrue(GitHubConfiguration.current(environment: [:]).isConfigured)
        XCTAssertEqual(GitHubConfiguration.current(environment: ["PTB_GITHUB_CLIENT_ID": "  local-id \n"]).clientID, "local-id")
        XCTAssertFalse(GitHubConfiguration(clientID: "").isConfigured)
        XCTAssertFalse(GitHubConfiguration(clientID: "id&scope=repo").isConfigured)
    }
}
