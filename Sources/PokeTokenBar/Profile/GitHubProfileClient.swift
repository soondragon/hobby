import Foundation

protocol GitHubProfileProviding: Sendable {
    func profile(accessToken: String) async throws -> GitHubProfile
}

struct GitHubProfileClient: GitHubProfileProviding {
    let transport: any GitHubHTTPTransport
    init(transport: any GitHubHTTPTransport = GitHubURLTransport()) { self.transport = transport }

    func profile(accessToken: String) async throws -> GitHubProfile {
        guard !accessToken.isEmpty, accessToken.count <= 4096,
              accessToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ProfileAccessError.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PokeTokenBar-Profile", forHTTPHeaderField: "User-Agent")
        let response = try await transport.send(request)
        try GitHubAuthenticationClient.validateStatus(response.status)
        let profile = try JSONDecoder().decode(GitHubProfile.self, from: response.data)
        guard profile.isValid else { throw ProfileAccessError.invalidResponse }
        return profile
    }
}
