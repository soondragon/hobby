import Foundation
import CryptoKit
import Security

/// Public-profile OAuth with state validation and S256 PKCE. No requested scopes.
struct GitHubProfileAuthorization: Sendable {
    let verifier: String
    let state: String
    let url: URL

    init(clientID: String) throws {
        guard !clientID.isEmpty, clientID.count <= 100,
              clientID.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { throw CloudError.configuration }
        verifier = try Self.random()
        state = try Self.random()
        let challenge = Self.encoded(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [.init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: "hobbytrainer://auth/callback"),
            .init(name: "scope", value: ""), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")]
        url = components.url!
    }

    func code(from callback: URL) throws -> String {
        guard callback.scheme == "hobbytrainer", callback.host == "auth", callback.path == "/callback",
              callback.user == nil, callback.password == nil, callback.port == nil, callback.fragment == nil,
              let parameters = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              parameters.filter({ $0.name == "state" }).count == 1,
              parameters.filter({ $0.name == "code" }).count == 1,
              !parameters.contains(where: { $0.name == "error" }),
              parameters.first(where: { $0.name == "state" })?.value == state,
              let code = parameters.first(where: { $0.name == "code" })?.value,
              (1...512).contains(code.count), code.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw CloudError.authentication
        }
        return code
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CloudError.authentication }
        return encoded(Data(bytes))
    }
    private static func encoded(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
