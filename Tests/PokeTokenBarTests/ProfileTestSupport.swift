import Foundation
import XCTest
@testable import PokeTokenBar

let sampleGitHubProfile = GitHubProfile(id: 42, login: "sample-trainer", name: "Sample Trainer")
let sampleDeviceAuthorization = DeviceAuthorization(deviceCode: "sample-device", userCode: "ABCD-1234",
    verificationURI: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5)

actor ProfileHTTPStub: GitHubHTTPTransport {
    var responses: [GitHubHTTPResponse]
    var requests: [URLRequest] = []
    init(_ responses: [GitHubHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> GitHubHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

actor AuthenticationStub: GitHubAuthenticating {
    var results: [AuthorizationPoll]
    var calls = 0
    var failure: ProfileAccessError?
    init(_ results: [AuthorizationPoll] = [.authorized(token: "test-token", expiresIn: 3600)], failure: ProfileAccessError? = nil) {
        self.results = results; self.failure = failure
    }
    func begin(clientID: String) throws -> DeviceAuthorization {
        if let failure { throw failure }
        return sampleDeviceAuthorization
    }
    func poll(clientID: String, deviceCode: String) throws -> AuthorizationPoll {
        calls += 1
        guard !results.isEmpty else { throw ProfileAccessError.expired }
        return results.removeFirst()
    }
}

struct ProfileProviderStub: GitHubProfileProviding {
    var value = sampleGitHubProfile
    var failure: ProfileAccessError?
    func profile(accessToken: String) throws -> GitHubProfile {
        if let failure { throw failure }
        return value
    }
}

actor SuspendedGitHubProfileProvider: GitHubProfileProviding {
    private var continuation: CheckedContinuation<GitHubProfile, Never>?
    var started = false
    func profile(accessToken: String) async -> GitHubProfile {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func complete() { continuation?.resume(returning: sampleGitHubProfile); continuation = nil }
}

@MainActor final class CredentialMemory: ProfileCredentialStoring {
    var value: GitHubCredential?
    var reads = 0
    var writes = 0
    var failWrites = false
    var failClear = false
    func read() -> GitHubCredential? { reads += 1; return value }
    func write(_ credential: GitHubCredential) throws {
        if failWrites { throw ProfileAccessError.storage }
        value = credential; writes += 1
    }
    func clear() throws {
        if failClear { throw ProfileAccessError.storage }
        value = nil
    }
}

@MainActor final class ProfileMemory: ProfilePersisting {
    var value: GitHubProfile?
    var failWrites = false
    func load(clientID: String) -> GitHubProfile? { value }
    func save(_ profile: GitHubProfile, clientID: String) throws {
        if failWrites { throw ProfileAccessError.storage }
        value = profile
    }
    func clear() { value = nil }
}

@MainActor final class ProfileTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var delays: [Double] = []
    func advance(_ seconds: Double) { delays.append(seconds); date.addTimeInterval(seconds) }
}

@MainActor func awaitProfileOperation(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<2000 {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Profile operation did not reach the expected state", file: file, line: line)
}
