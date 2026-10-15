import Foundation
import Observation

/// Owns authentication lifetime independently of the transient menu-bar popover.
@MainActor @Observable
final class ProfileSession {
    private(set) var profile: GitHubProfile?
    private(set) var isVerified = false
    private(set) var isBusy = false
    private(set) var challenge: DeviceAuthorization?
    private(set) var error: ProfileAccessError?
    let configuration: GitHubConfiguration

    private let authentication: any GitHubAuthenticating
    private let profiles: any GitHubProfileProviding
    private let credentials: any ProfileCredentialStoring
    private let repository: any ProfilePersisting
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var operation: Task<Void, Never>?
    private var generation = 0

    init(configuration: GitHubConfiguration, authentication: any GitHubAuthenticating,
         profiles: any GitHubProfileProviding, credentials: any ProfileCredentialStoring,
         repository: any ProfilePersisting, now: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         }) {
        self.configuration = configuration
        self.authentication = authentication
        self.profiles = profiles
        self.credentials = credentials
        self.repository = repository
        self.now = now
        self.sleep = sleep
        // Cached public identity is display-only. No credentials are read at startup.
        do { profile = try repository.load(clientID: configuration.clientID) }
        catch { self.error = .storage }
    }

    func signIn() {
        guard !isBusy else { return }
        guard configuration.isConfigured else { error = .notConfigured; return }
        start { session, generation in await session.authorize(generation: generation) }
    }

    /// Explicit user action: allows a Keychain prompt and revalidates /user, including renamed aliases.
    func verifySavedProfile() {
        guard !isBusy else { return }
        guard configuration.isConfigured else { error = .notConfigured; return }
        start { session, generation in
            do {
                guard let credential = try session.credentials.read() else { throw ProfileAccessError.invalidCredential }
                guard credential.clientID == session.configuration.clientID,
                      credential.expiresAt.map({ $0 > session.now() }) ?? true else { throw ProfileAccessError.expired }
                let profile = try await session.profiles.profile(accessToken: credential.accessToken)
                guard session.generation == generation, !Task.isCancelled else { return }
                guard profile.isValid, profile.id == credential.userID else { throw ProfileAccessError.invalidCredential }
                try session.repository.save(profile, clientID: session.configuration.clientID)
                session.profile = profile
                session.isVerified = true
                session.finish(generation: generation)
            } catch { session.fail(error, generation: generation) }
        }
    }

    func cancel() {
        generation += 1
        operation?.cancel()
        operation = nil
        challenge = nil
        isBusy = false
    }

    func disconnect() {
        cancel()
        isVerified = false
        do {
            try credentials.clear()
            try repository.clear()
            profile = nil
            error = nil
        } catch { self.error = .storage }
    }

    private func start(_ action: @escaping @MainActor (ProfileSession, Int) async -> Void) {
        generation += 1
        let current = generation
        error = nil
        isBusy = true
        operation = Task { await action(self, current) }
    }

    private func authorize(generation: Int) async {
        do {
            let challenge = try await authentication.begin(clientID: configuration.clientID)
            guard self.generation == generation, !Task.isCancelled else { return }
            guard challenge.isValid else { throw ProfileAccessError.invalidResponse }
            self.challenge = challenge
            let deadline = now().addingTimeInterval(Double(challenge.expiresIn))
            var interval = Double(challenge.interval)
            while now() < deadline {
                try await sleep(min(interval, max(0, deadline.timeIntervalSince(now()))))
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                guard now() < deadline else { throw ProfileAccessError.expired }
                let result = try await authentication.poll(clientID: configuration.clientID, deviceCode: challenge.deviceCode)
                guard self.generation == generation, !Task.isCancelled else { return }
                switch result {
                case .pending: continue
                case .slowDown: interval += 5
                case .authorized(let token, let expiresIn):
                    let profile = try await profiles.profile(accessToken: token)
                    guard self.generation == generation, !Task.isCancelled else { return }
                    guard now() < deadline else { throw ProfileAccessError.expired }
                    guard profile.isValid else { throw ProfileAccessError.invalidResponse }
                    try credentials.write(GitHubCredential(
                        clientID: configuration.clientID, userID: profile.id, accessToken: token,
                        expiresAt: expiresIn.map { now().addingTimeInterval(Double($0)) }))
                    do { try repository.save(profile, clientID: configuration.clientID) }
                    catch {
                        // A partial save cannot be advertised as a completed sign-in.
                        try credentials.clear()
                        throw ProfileAccessError.storage
                    }
                    self.profile = profile
                    isVerified = true
                    finish(generation: generation)
                    return
                }
            }
            throw ProfileAccessError.expired
        } catch { fail(error, generation: generation) }
    }

    private func finish(generation: Int) {
        guard self.generation == generation else { return }
        challenge = nil
        isBusy = false
        operation = nil
    }

    private func fail(_ error: any Error, generation: Int) {
        guard self.generation == generation else { return }
        isVerified = false
        if !(error is CancellationError) {
            self.error = error as? ProfileAccessError ?? .unavailable
        }
        finish(generation: generation)
    }
}
