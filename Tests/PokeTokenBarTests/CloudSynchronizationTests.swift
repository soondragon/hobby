import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
private final class CloudTestAuthentication: CloudAuthenticating {
    var userID: UUID?
    var rejectSignOut = false
    init(_ owner: UUID) { userID = owner }
    func signIn() async throws {}
    func restore() async throws {}
    func accessToken() async throws -> String { "test-session" }
    func signOut() async throws { if rejectSignOut { throw CloudError.transport }; userID = nil }
}

private actor CloudTestRepository: CloudSaveServing {
    let owner: UUID
    var state: CompanionState?
    var revision: Int
    var commands: [CloudSaveCommand] = []
    var failNextReceipt = false
    var rejectConflicts = false
    var deferNext = false
    var operations: [UUID: CloudSaveReceipt] = [:]
    init(owner: UUID, state: CompanionState? = nil) {
        self.owner = owner; self.state = state; revision = state == nil ? 0 : 1
    }
    func failReceipt() { failNextReceipt = true }
    func conflict() { rejectConflicts = true }
    func receipts() -> [CloudSaveCommand] { commands }
    func read(token: String) async throws -> CloudSaveEnvelope {
        .init(ownerID: owner, alias: "trainer", schemaVersion: 1, revision: revision, state: state)
    }
    func deferOnce() { deferNext = true }

    func write(_ command: CloudSaveCommand, token: String) async throws -> CloudSaveReceipt {
        commands.append(command)
        if deferNext { deferNext = false; throw CloudError.saveDeferred(1) }
        if rejectConflicts { throw CloudError.conflict }
        if let existing = operations[command.requestID] { return existing }
        guard revision == command.expectedRevision else { throw CloudError.conflict }
        revision += 1; state = command.state
        let receipt = CloudSaveReceipt(ownerID: owner, revision: revision, requestID: command.requestID)
        operations[command.requestID] = receipt
        if failNextReceipt { failNextReceipt = false; throw CloudError.transport }
        return receipt
    }
}

@MainActor
final class CloudSynchronizationTests: XCTestCase {
    private let configuration = CloudConfiguration(supabaseURL: URL(string: "https://example.supabase.co")!,
        publishableKey: "sb_publishable_example", serviceURL: URL(string: "https://example.vercel.app")!)

    func testLogoutReportsFailureUntilServerRevocationSucceeds() async {
        let owner = UUID()
        let store = CompanionStore(cloudMode: true)
        let authentication = CloudTestAuthentication(owner)
        let controller = CloudCompanionController(store: store, configuration: configuration,
            authentication: authentication, repository: CloudTestRepository(owner: owner, state: CompanionState()))
        await controller.connect()
        authentication.rejectSignOut = true
        await controller.disconnect()
        XCTAssertNotNil(controller.alias)
        XCTAssertNotNil(authentication.userID)
        authentication.rejectSignOut = false
        await controller.disconnect()
        XCTAssertNil(controller.alias)
        XCTAssertNil(authentication.userID)
        XCTAssertFalse(store.canModifyCompanion)
    }

    func testLostAcknowledgementRetriesIdenticalCommandWithoutDuplicatingState() async throws {
        let owner = UUID()
        let store = CompanionStore(cloudMode: true)
        let repository = CloudTestRepository(owner: owner)
        let controller = CloudCompanionController(store: store, configuration: configuration,
            authentication: CloudTestAuthentication(owner), repository: repository)
        await controller.connect()
        await repository.failReceipt()
        await controller.initialize()
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertTrue(controller.canRetry)
        XCTAssertFalse(store.canModifyCompanion)
        await controller.retry()
        let commands = await repository.receipts()
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].requestID, commands[1].requestID)
        XCTAssertEqual(commands[0].expectedRevision, commands[1].expectedRevision)
        XCTAssertTrue(store.canModifyCompanion)
        XCTAssertFalse(controller.hasUnsavedChanges)
    }

    func testConflictFreezesGameplayAndRequiresExplicitDiscardBeforeReload() async throws {
        let owner = UUID()
        let store = CompanionStore(cloudMode: true)
        var remote = CompanionState()
        remote.language = .en
        let repository = CloudTestRepository(owner: owner, state: remote)
        let controller = CloudCompanionController(store: store, configuration: configuration,
            authentication: CloudTestAuthentication(owner), repository: repository)
        await controller.connect()
        await repository.conflict()
        store.setLanguage(.ko)
        // Wait on the real debounce branch, with a bounded deadline.
        for _ in 0..<100 {
            if !store.canModifyCompanion { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertFalse(controller.canRetry)
        XCTAssertFalse(store.canModifyCompanion)
        await controller.reload()
        XCTAssertFalse(store.canModifyCompanion)
        await controller.discardAndReload()
        XCTAssertTrue(store.canModifyCompanion)
        XCTAssertEqual(store.language, .en)
    }

    func testDeferredSaveAutomaticallyRetriesIdenticalRequest() async throws {
        let owner = UUID(); let store = CompanionStore(cloudMode: true)
        let repository = CloudTestRepository(owner: owner)
        let controller = CloudCompanionController(store: store, configuration: configuration,
            authentication: CloudTestAuthentication(owner), repository: repository)
        await controller.connect()
        await repository.deferOnce()
        await controller.initialize()
        XCTAssertTrue(controller.hasUnsavedChanges)
        for _ in 0..<150 {
            if !controller.hasUnsavedChanges { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let commands = await repository.receipts()
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.first?.requestID, commands.last?.requestID)
        XCTAssertFalse(controller.hasUnsavedChanges)
    }

    func testForeignOwnerResponseNeverBecomesPlayerState() async {
        let store = CompanionStore(cloudMode: true)
        let controller = CloudCompanionController(store: store, configuration: configuration,
            authentication: CloudTestAuthentication(UUID()), repository: CloudTestRepository(owner: UUID(), state: CompanionState()))
        await controller.connect()
        XCTAssertNil(controller.alias)
        XCTAssertFalse(store.canModifyCompanion)
    }
}
