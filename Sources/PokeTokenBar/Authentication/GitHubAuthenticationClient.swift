import Foundation

protocol GitHubAuthenticating: Sendable {
    func begin(clientID: String) async throws -> DeviceAuthorization
    func poll(clientID: String, deviceCode: String) async throws -> AuthorizationPoll
}

struct GitHubAuthenticationClient: GitHubAuthenticating {
    let transport: any GitHubHTTPTransport
    init(transport: any GitHubHTTPTransport = GitHubURLTransport()) { self.transport = transport }

    func begin(clientID: String) async throws -> DeviceAuthorization {
        guard GitHubConfiguration(clientID: clientID).isConfigured else { throw ProfileAccessError.notConfigured }
        let response = try await transport.send(Self.request(path: "/login/device/code", parameters: ["client_id": clientID]))
        try Self.validateStatus(response.status)
        let challenge = try JSONDecoder().decode(DeviceAuthorization.self, from: response.data)
        guard challenge.isValid else { throw ProfileAccessError.invalidResponse }
        return challenge
    }

    func poll(clientID: String, deviceCode: String) async throws -> AuthorizationPoll {
        let response = try await transport.send(Self.request(path: "/login/oauth/access_token", parameters: [
            "client_id": clientID, "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]))
        try Self.validateStatus(response.status)
        let result = try JSONDecoder().decode(TokenResponse.self, from: response.data)
        if let error = result.error {
            switch error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "access_denied": throw ProfileAccessError.denied
            case "expired_token", "token_expired": throw ProfileAccessError.expired
            case "incorrect_client_credentials", "device_flow_disabled": throw ProfileAccessError.notConfigured
            default: throw ProfileAccessError.invalidResponse
            }
        }
        guard let token = result.accessToken, !token.isEmpty, token.count <= 4096,
              result.tokenType?.lowercased() == "bearer",
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              // This dedicated registration must not request repository, email or workflow permissions.
              (result.scope ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.expiresIn.map({ $0 > 0 }) ?? true else { throw ProfileAccessError.invalidResponse }
        return .authorized(token: token, expiresIn: result.expiresIn)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let tokenType: String?
        let scope: String?
        let expiresIn: Int?
        let error: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", tokenType = "token_type", expiresIn = "expires_in", scope, error
        }
    }

    static func request(path: String, parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://github.com" + path)!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PokeTokenBar-Profile", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = parameters.sorted { $0.key < $1.key }.map {
            ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "="
                + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").data(using: .utf8)
        return request
    }

    static func validateStatus(_ status: Int) throws {
        switch status {
        case 200: return
        case 401: throw ProfileAccessError.invalidCredential
        case 403, 429: throw ProfileAccessError.rateLimited
        case 500...599: throw ProfileAccessError.unavailable
        default: throw ProfileAccessError.invalidResponse
        }
    }
}
