import AppKit
import AuthenticationServices
import CryptoKit
import Security

struct CloudUser: Decodable, Sendable {
    struct Identity: Decodable, Sendable { let provider: String }
    let id: UUID
    let identities: [Identity]
}

@MainActor
final class CloudAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding, CloudAuthenticating {
    private let configuration: CloudConfiguration
    private let transport = CloudTransport()
    private let persistCredentials: Bool
    private var browserSession: ASWebAuthenticationSession?
    private var credential: CloudCredential?
    private var expiresAt = Date.distantPast
    private(set) var user: CloudUser?
    var userID: UUID? { user?.id }
    private var refreshTask: Task<CloudCredential, Error>?
    private var generation = UUID()

    init(configuration: CloudConfiguration, persistCredentials: Bool = true) {
        self.configuration = configuration
        self.persistCredentials = persistCredentials
    }
    private var vault: CloudCredentialVault { .init(project: configuration.supabaseURL.absoluteString) }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    func signIn() async throws {
        let operation = generation
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CloudError.authentication }
        let verifier = Data(bytes).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var url = URLComponents(url: configuration.supabaseURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "provider", value: "github"),
                          .init(name: "redirect_to", value: "hobbytrainer://auth/callback"),
                          .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "s256")]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let completion = CloudBrowserCompletion(continuation)
            let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "hobbytrainer", completionHandler: completion.handler)
            session.presentationContextProvider = self
            // Use the user's configured browser rather than choosing another Chrome profile.
            session.prefersEphemeralWebBrowserSession = false
            browserSession = session
            if !session.start() { completion.finish(url: nil) }
        }
        browserSession = nil
        guard operation == generation, callback.scheme == "hobbytrainer", callback.host == "auth", callback.path == "/callback",
              let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CloudError.authentication
        }
        let value = try await exchange(grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
        guard operation == generation else { throw CancellationError() }
        try await accept(value, operation: operation)
    }

    func restore() async throws {
        let operation = generation
        guard persistCredentials, let previous = try vault.read() else { throw CloudError.authentication }
        let value = try await exchange(grant: "refresh_token", body: ["refresh_token": previous.refresh_token])
        guard operation == generation else { throw CancellationError() }
        try await accept(value, operation: operation)
    }

    private func exchange(grant: String, body: [String: String]) async throws -> CloudCredential {
        var url = URLComponents(url: configuration.supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "grant_type", value: grant)]
        return try await transport.request(CloudCredential.self, url: url.url!, method: "POST", key: configuration.publishableKey,
                                           body: JSONEncoder().encode(body))
    }

    private func accept(_ value: CloudCredential, operation: UUID) async throws {
        let verified = try await transport.request(CloudUser.self, url: configuration.supabaseURL.appendingPathComponent("auth/v1/user"),
                                                    token: value.access_token, key: configuration.publishableKey)
        guard operation == generation else { throw CancellationError() }
        guard verified.identities.contains(where: { $0.provider == "github" }) else { throw CloudError.authentication }
        if persistCredentials { try vault.write(value) }
        credential = value
        user = verified
        expiresAt = Date().addingTimeInterval(Double(max(0, value.expires_in - 60)))
    }

    func accessToken() async throws -> String {
        guard let credential, user != nil else { throw CloudError.authentication }
        if Date() < expiresAt { return credential.access_token }
        let operation = generation
        let task: Task<CloudCredential, Error>
        if let refreshTask { task = refreshTask }
        else {
            task = Task { try await self.exchange(grant: "refresh_token", body: ["refresh_token": credential.refresh_token]) }
            refreshTask = task
        }
        defer { if operation == generation { refreshTask = nil } }
        let value = try await task.value
        guard operation == generation else { throw CancellationError() }
        try await accept(value, operation: operation)
        return value.access_token
    }

    func signOut() async throws {
        // Revoke only this device's session. Other signed-in devices stay connected.
        if credential != nil {
            let token = try await accessToken()
            var endpoint = URLComponents(url: configuration.supabaseURL.appendingPathComponent("auth/v1/logout"), resolvingAgainstBaseURL: false)!
            endpoint.queryItems = [.init(name: "scope", value: "local")]
            let _: CloudEmptyResponse = try await transport.request(CloudEmptyResponse.self, url: endpoint.url!,
                method: "POST", token: token, key: configuration.publishableKey)
        }
        generation = UUID()
        browserSession?.cancel()
        browserSession = nil
        refreshTask?.cancel()
        refreshTask = nil
        credential = nil
        user = nil
        expiresAt = .distantPast
        if persistCredentials { try vault.clear() }
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
