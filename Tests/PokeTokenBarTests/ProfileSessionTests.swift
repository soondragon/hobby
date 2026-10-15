import XCTest
@testable import PokeTokenBar

@MainActor
final class ProfileSessionTests: XCTestCase {
    private let configuration = GitHubConfiguration(clientID: "test-client")

    private func session(authentication: any GitHubAuthenticating = AuthenticationStub(),
                         provider: any GitHubProfileProviding = ProfileProviderStub(),
                         vault: CredentialMemory = CredentialMemory(), cache: ProfileMemory = ProfileMemory(),
                         clock: ProfileTestClock = ProfileTestClock()) -> ProfileSession {
        ProfileSession(configuration: configuration, authentication: authentication, profiles: provider,
                       credentials: vault, repository: cache, now: { clock.date },
                       sleep: { delay in await clock.advance(delay) })
    }

    func testSignInWaitsAndBacksOffBeforeSavingVerifiedAlias() async {
        let vault = CredentialMemory(), cache = ProfileMemory(), clock = ProfileTestClock()
        let auth = AuthenticationStub([.pending, .slowDown, .authorized(token: "sample-token", expiresIn: 3600)])
        let session = session(authentication: auth, vault: vault, cache: cache, clock: clock)
        session.signIn()
        session.signIn() // A rapid second click cannot start another request chain.
        await awaitProfileOperation { !session.isBusy }
        XCTAssertEqual(clock.delays, [5, 5, 10])
        XCTAssertEqual(session.profile?.alias, "@sample-trainer")
        XCTAssertTrue(session.isVerified)
        XCTAssertNil(session.challenge)
        XCTAssertEqual(vault.writes, 1)
        XCTAssertEqual(vault.value?.userID, 42)
        XCTAssertEqual(cache.value, sampleGitHubProfile)
    }

    func testStartupDisplaysCacheWithoutReadingKeychainOrTrustingIt() {
        let vault = CredentialMemory(), cache = ProfileMemory()
        cache.value = sampleGitHubProfile
        let session = session(vault: vault, cache: cache)
        XCTAssertEqual(session.profile?.alias, "@sample-trainer")
        XCTAssertFalse(session.isVerified)
        XCTAssertEqual(vault.reads, 0)
    }

    func testExplicitVerificationRefreshesAliasByStableID() async {
        let vault = CredentialMemory(), cache = ProfileMemory()
        cache.value = sampleGitHubProfile
        vault.value = GitHubCredential(clientID: "test-client", userID: 42, accessToken: "sample-token", expiresAt: nil)
        let renamed = GitHubProfile(id: 42, login: "new-name", name: nil)
        let session = session(provider: ProfileProviderStub(value: renamed), vault: vault, cache: cache)
        session.verifySavedProfile()
        await awaitProfileOperation { !session.isBusy }
        XCTAssertEqual(session.profile?.alias, "@new-name")
        XCTAssertTrue(session.isVerified)
        XCTAssertEqual(vault.reads, 1)
        XCTAssertEqual(cache.value, renamed)
    }

    func testMismatchedOrExpiredCredentialNeverVerifiesCache() async {
        for expired in [false, true] {
            let vault = CredentialMemory(), cache = ProfileMemory()
            cache.value = sampleGitHubProfile
            vault.value = GitHubCredential(clientID: "test-client", userID: expired ? 42 : 99,
                accessToken: "sample-token", expiresAt: expired ? .distantPast : nil)
            let session = session(vault: vault, cache: cache)
            session.verifySavedProfile()
            await awaitProfileOperation { !session.isBusy }
            XCTAssertFalse(session.isVerified)
            XCTAssertEqual(session.error, expired ? .expired : .invalidCredential)
            XCTAssertEqual(cache.value, sampleGitHubProfile)
        }
    }

    func testDeniedAndStorageFailureDoNotPublishAuthenticatedProfile() async {
        let denied = session(authentication: AuthenticationStub(failure: .denied))
        denied.signIn()
        await awaitProfileOperation { !denied.isBusy }
        XCTAssertEqual(denied.error, .denied)
        XCTAssertNil(denied.profile)
        let vault = CredentialMemory(), cache = ProfileMemory()
        cache.failWrites = true
        let failed = session(vault: vault, cache: cache)
        failed.signIn()
        await awaitProfileOperation { !failed.isBusy }
        XCTAssertEqual(failed.error, .storage)
        XCTAssertNil(vault.value)
        XCTAssertNil(failed.profile)
        XCTAssertFalse(failed.isVerified)
    }

    func testExpiryStopsPollingAtDeadline() async {
        let clock = ProfileTestClock()
        let session = ProfileSession(configuration: configuration, authentication: AuthenticationStub([.pending]),
            profiles: ProfileProviderStub(), credentials: CredentialMemory(), repository: ProfileMemory(),
            now: { clock.date }, sleep: { _ in await clock.advance(901) })
        session.signIn()
        await awaitProfileOperation { !session.isBusy }
        XCTAssertEqual(session.error, .expired)
        XCTAssertNil(session.profile)
    }

    func testDisconnectRejectsLateSuccessAfterCancellation() async {
        let provider = SuspendedGitHubProfileProvider(), vault = CredentialMemory(), cache = ProfileMemory()
        let session = session(provider: provider, vault: vault, cache: cache)
        session.signIn()
        for _ in 0..<2000 {
            if await provider.started { break }
            await Task.yield()
        }
        XCTAssertTrue(session.isBusy)
        session.disconnect()
        await provider.complete()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertNil(session.profile)
        XCTAssertNil(vault.value)
        XCTAssertNil(cache.value)
        XCTAssertFalse(session.isBusy)
    }

    func testDisconnectFailureIsVisible() {
        let vault = CredentialMemory(), cache = ProfileMemory()
        vault.failClear = true
        cache.value = sampleGitHubProfile
        let session = session(vault: vault, cache: cache)
        session.disconnect()
        XCTAssertEqual(session.error, .storage)
        XCTAssertNotNil(session.profile)
        XCTAssertFalse(session.isVerified)
    }

    func testPublicCacheIsSeparateFromCompanionAndNeverContainsTokens() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let companion = root.appendingPathComponent("companion-state.json")
        let original = Data("unchanged-pokemon-state".utf8)
        try original.write(to: companion)
        let file = root.appendingPathComponent("user-profile.json")
        let repository = ProfileRepository(fileURL: file)
        try repository.save(sampleGitHubProfile, clientID: "test-client")
        XCTAssertEqual(try repository.load(clientID: "test-client"), sampleGitHubProfile)
        XCTAssertNil(try repository.load(clientID: "other-client"))
        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("sample-token"))
        try repository.clear()
        XCTAssertEqual(try Data(contentsOf: companion), original)
    }
}
