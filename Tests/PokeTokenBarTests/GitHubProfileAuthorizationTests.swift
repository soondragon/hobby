import XCTest
import CryptoKit
@testable import PokeTokenBar

final class GitHubProfileAuthorizationTests: XCTestCase {
    func testAuthorizationRequestsNoScopesAndBindsStrongPKCE() throws {
        let flow = try GitHubProfileAuthorization(clientID: "ExampleClient")
        let parameters = Dictionary(uniqueKeysWithValues: URLComponents(url: flow.url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(flow.url.host, "github.com")
        XCTAssertEqual(parameters["scope"], "")
        XCTAssertEqual(parameters["code_challenge_method"], "S256")
        XCTAssertEqual(parameters["redirect_uri"], "hobbytrainer://auth/callback")
        XCTAssertEqual(flow.verifier.count, 43)
        let expected = Data(SHA256.hash(data: Data(flow.verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(parameters["code_challenge"], expected)
        XCTAssertNotEqual(flow.state, try GitHubProfileAuthorization(clientID: "ExampleClient").state)
        XCTAssertEqual(try flow.code(from: URL(string: "hobbytrainer://auth/callback?state=\(flow.state)&code=valid_code")!), "valid_code")
    }

    func testRejectsStateForgeryDuplicateCodeAndWrongCallbacks() throws {
        let flow = try GitHubProfileAuthorization(clientID: "ExampleClient")
        for callback in ["hobbytrainer://auth/callback?state=other&code=valid",
                         "hobbytrainer://auth/callback?state=\(flow.state)&code=a&code=b",
                         "hobbytrainer://auth/callback?state=\(flow.state)&state=bad&code=a",
                         "hobbytrainer://attacker/callback?state=\(flow.state)&code=a",
                         "https://auth/callback?state=\(flow.state)&code=a",
                         "hobbytrainer://auth/callback?state=\(flow.state)&code=a&error=denied"] {
            XCTAssertThrowsError(try flow.code(from: URL(string: callback)!))
        }
    }
}
