import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
final class CloudPersistenceTests: XCTestCase {
    func testAuthenticationCallbackCanResumeFromBackgroundXPCQueueExactlyOnce() async throws {
        let expected = URL(string: "hobbytrainer://auth/callback?code=example")!
        let actual: URL = try await withCheckedThrowingContinuation { continuation in
            let callback = CloudBrowserCompletion(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                callback.handler(expected, nil)
                // A late cancellation/start failure must not resume a second time.
                callback.finish(url: nil)
            }
        }
        XCTAssertEqual(actual, expected)
    }

    func testCloudStartupNeverReadsOrWritesLocalSaveAndBlocksGameplay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("companion-state.json")
        var original = CompanionState()
        original.usedSinceInstall = 999
        original.inventory = ["mint": 3]
        let originalBytes = try JSONEncoder().encode(original)
        try originalBytes.write(to: url)
        let store = CompanionStore(fileURL: url, cloudMode: true)
        XCTAssertEqual(store.state.usedSinceInstall, 0)
        XCTAssertFalse(store.canModifyCompanion)
        store.applyUsage(100)
        XCTAssertFalse(store.buy(.mint))
        store.setLanguage(.ko)
        XCTAssertEqual(store.state.usedSinceInstall, 0)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertTrue(store.availableSnapshots.isEmpty)
        XCTAssertThrowsError(try store.createManualSnapshot())
    }

    func testCloudMutationUsesInjectedSinkAndAccountResetClearsPlayerState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CompanionStore(fileURL: url, cloudMode: true)
        var remote = CompanionState()
        remote.usedSinceInstall = 42
        remote.inventory = ["mint": 2]
        var received: CompanionState?
        store.onCloudMutation = { received = $0 }
        store.replaceCloudState(remote, writable: true)
        store.setLanguage(.ko)
        XCTAssertEqual(received?.usedSinceInstall, 42)
        XCTAssertEqual(received?.language, .ko)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.replaceCloudState(CompanionState(), writable: false)
        XCTAssertEqual(store.state.inventory, [:])
        XCTAssertEqual(store.state.usedSinceInstall, 0)
        XCTAssertFalse(store.canModifyCompanion)
    }

    func testCloudLegacyProfileMigrationNeverCreatesLocalBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("companion-state.json")
        let original = Data("local save must remain untouched".utf8)
        try original.write(to: url)
        let store = CompanionStore(fileURL: url, cloudMode: true)
        var remote = CompanionState()
        remote.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1,2,3], stageIndex: 0,
                                 usedAtStage: 1, rarity: .rare, totalForms: 3)
        store.restoreCloudRules(growth: 0.5, shop: 1.5)
        store.replaceCloudState(remote, writable: true)
        XCTAssertNotNil(store.state.active?.profile)
        XCTAssertEqual(store.growthDifficulty, 0.5)
        XCTAssertEqual(store.shopDifficulty, 1.5)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["companion-state.json"])
    }

    func testConfigurationRejectsSecretsAndInsecureOrigins() {
        let valid = CloudConfiguration(supabaseURL: URL(string: "https://example.supabase.co")!,
                                      publishableKey: "sb_publishable_example", serviceURL: URL(string: "https://example.vercel.app")!)
        XCTAssertNoThrow(try valid.validate())
        let secret = CloudConfiguration(supabaseURL: valid.supabaseURL, publishableKey: "sb_secret_example", serviceURL: valid.serviceURL)
        XCTAssertThrowsError(try secret.validate())
        let insecure = CloudConfiguration(supabaseURL: valid.supabaseURL, publishableKey: valid.publishableKey, serviceURL: URL(string: "http://example.com")!)
        XCTAssertThrowsError(try insecure.validate())
    }
}
