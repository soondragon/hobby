import Foundation

@MainActor
enum ProfileSessionFactory {
    static func live(configuration: GitHubConfiguration = .current(), directory: URL) -> ProfileSession {
        ProfileSession(configuration: configuration,
            authentication: GitHubAuthenticationClient(), profiles: GitHubProfileClient(),
            credentials: ProfileCredentialVault(clientID: configuration.clientID),
            repository: ProfileRepository(fileURL: directory.appendingPathComponent("user-profile.json")))
    }
}
