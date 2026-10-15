import AppKit
import AuthenticationServices

struct CloudUser: Decodable, Sendable {
    let id: UUID
    let alias: String
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
    private var vault: CloudCredentialVault { .init(project: configuration.serviceURL.absoluteString + "/public-profile-v1") }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    func signIn() async throws {
        let operation = generation
        guard let clientID = configuration.githubClientID else { throw CloudError.configuration }
        let authorization = try GitHubProfileAuthorization(clientID: clientID)
        let callback: URL
        #if DEBUG
        if ProcessInfo.processInfo.environment["TRAINER_PROFILE_MANUAL_BROWSER"] == "1" {
            callback = try await ManualProfileBrowser.authorize(authorization.url)
        } else {
            callback = try await browserCallback(authorization.url)
        }
        #else
        callback = try await browserCallback(authorization.url)
        #endif
        browserSession = nil
        guard operation == generation else { throw CancellationError() }
        let code = try authorization.code(from: callback)
        let value = try await exchange(path: "github/exchange", body: ["code": code, "verifier": authorization.verifier])
        guard operation == generation else { throw CancellationError() }
        try await accept(value, operation: operation)
    }

    private func browserCallback(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion = CloudBrowserCompletion(continuation)
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "hobbytrainer", completionHandler: completion.handler)
            session.presentationContextProvider = self
            // Use the user's configured browser rather than choosing another Chrome profile.
            session.prefersEphemeralWebBrowserSession = false
            browserSession = session
            if !session.start() { completion.finish(url: nil) }
        }
    }

    func restore() async throws {
        let operation = generation
        guard persistCredentials, let previous = try vault.read() else { throw CloudError.authentication }
        let value = try await exchange(path: "refresh", body: ["refresh_token": previous.refresh_token])
        guard operation == generation else { throw CancellationError() }
        try await accept(value, operation: operation)
    }

    private func exchange(path: String, body: [String: String]) async throws -> CloudCredential {
        try await transport.request(CloudCredential.self,
            url: configuration.serviceURL.appendingPathComponent("api/auth/" + path), method: "POST",
            body: JSONEncoder().encode(body))
    }

    private func accept(_ value: CloudCredential, operation: UUID) async throws {
        let verified = try await transport.request(CloudUser.self, url: configuration.serviceURL.appendingPathComponent("api/auth/user"),
                                                    token: value.access_token)
        guard operation == generation else { throw CancellationError() }
        guard value.access_token.hasPrefix("hts_"), value.refresh_token.hasPrefix("htr_"),
              (1...900).contains(value.expires_in), !verified.alias.isEmpty, verified.alias.count <= 39 else { throw CloudError.authentication }
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
            task = Task { try await self.exchange(path: "refresh", body: ["refresh_token": credential.refresh_token]) }
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
            let _: CloudEmptyResponse = try await transport.request(CloudEmptyResponse.self,
                url: configuration.serviceURL.appendingPathComponent("api/auth/logout"), method: "POST", token: token)
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
