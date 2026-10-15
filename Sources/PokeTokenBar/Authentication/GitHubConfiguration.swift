import Foundation

struct GitHubConfiguration: Sendable {
    // Public OAuth application identifier, not a client secret.
    static let defaultClientID = "Ov23liApOfXUQ1ZOY1C3"
    let clientID: String

    var isConfigured: Bool {
        !clientID.isEmpty && clientID.count <= 128 && clientID.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 46 || $0 == 95 || $0 == 45
        }
    }

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment,
                        bundle: Bundle = .main) -> Self {
        Self(clientID: (environment["PTB_GITHUB_CLIENT_ID"]
            ?? bundle.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? defaultClientID)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
