import Foundation
import Observation

struct CloudSaveEnvelope: Decodable, Sendable {
    let ownerID: UUID
    let alias: String
    let schemaVersion: Int
    let revision: Int
    let state: CompanionState?
    var rules: CloudRuleSettings? = nil
}

struct CloudRuleSettings: Codable, Sendable {
    var growthDifficulty: Double = 1
    var shopDifficulty: Double = 1
}

struct CloudSaveCommand: Encodable, Sendable {
    let schemaVersion = 1
    let expectedRevision: Int
    let requestID: UUID
    let operation: String
    let state: CompanionState
    var rules = CloudRuleSettings()
}

struct CloudSaveReceipt: Decodable, Sendable {
    let ownerID: UUID
    let revision: Int
    let requestID: UUID
}

@MainActor
@Observable
final class CloudCompanionController {
    private(set) var alias: String?
    private(set) var status = "GitHub 로그인 후 서버 세이브를 불러오세요."
    private(set) var isBusy = false
    private(set) var hasRemoteSave = false
    private(set) var hasUnsavedChanges = false
    private(set) var canRetry = false
    let isConfigured: Bool
    private let repository: (any CloudSaveServing)?
    private let authentication: (any CloudAuthenticating)?
    private weak var store: CompanionStore?
    private var revision = 0
    private(set) var ownerID: UUID?
    private var generation = UUID()
    private var pending: CompanionState?
    private var inFlight: CloudSaveCommand?
    private var worker: Task<Void, Never>?
    private var retryWorker: Task<Void, Never>?

    init(store: CompanionStore, configuration: CloudConfiguration?,
         authentication: (any CloudAuthenticating)? = nil, repository: (any CloudSaveServing)? = nil) {
        self.store = store
        self.repository = repository ?? configuration.map(CloudSaveRepository.init)
        self.authentication = authentication ?? configuration.map { CloudAuthentication(configuration: $0) }
        isConfigured = configuration != nil
        if configuration == nil { status = CloudError.configuration.localizedDescription }
        store.onCloudMutation = { [weak self] state in self?.enqueue(state) }
    }

    func encounterToken() async throws -> String {
        guard alias != nil, let authentication else { throw CloudError.authentication }
        return try await authentication.accessToken()
    }

    func connect(restore: Bool = false) async {
        guard !isBusy, !hasUnsavedChanges, let authentication else { return }
        isBusy = true
        let operation = generation
        defer { if operation == generation { isBusy = false; schedulePending() } }
        store?.setCloudWritable(false)
        do {
            if restore { try await authentication.restore() } else { try await authentication.signIn() }
            guard operation == generation else { return }
            try await load(operation: operation)
        } catch { if operation == generation { status = error.localizedDescription } }
    }

    func reload() async {
        guard !isBusy, !hasUnsavedChanges else { return }
        isBusy = true
        let operation = generation
        store?.setCloudWritable(false)
        defer { if operation == generation { isBusy = false; schedulePending() } }
        do { try await load(operation: operation) }
        catch { if operation == generation { status = error.localizedDescription } }
    }

    private func load(operation: UUID) async throws {
        guard let authentication, let repository else { throw CloudError.configuration }
        let token = try await authentication.accessToken()
        let result = try await repository.read(token: token)
        guard operation == generation else { throw CancellationError() }
        guard result.ownerID == authentication.userID, result.schemaVersion == 1,
              result.revision >= 0, result.revision < SaveTransfer.maxTokenValue,
              !result.alias.isEmpty, result.alias.count <= 100,
              (result.revision == 0) == (result.state == nil) else { throw CloudError.invalidResponse }
        alias = "@" + result.alias
        ownerID = result.ownerID
        revision = result.revision
        hasRemoteSave = result.state != nil
        let rules = result.rules ?? CloudRuleSettings()
        guard rules.growthDifficulty.isFinite, rules.shopDifficulty.isFinite,
              (0.1...2).contains(rules.growthDifficulty), (0.1...2).contains(rules.shopDifficulty) else { throw CloudError.invalidResponse }
        store?.restoreCloudRules(growth: rules.growthDifficulty, shop: rules.shopDifficulty)
        if let state = result.state {
            store?.replaceCloudState(state, writable: true)
            status = "서버 세이브 연결됨 · 버전 \(revision)"
        } else {
            store?.replaceCloudState(CompanionState(), writable: false)
            status = CloudError.missingSave.localizedDescription
        }
    }

    /// Creates a new server save; no local Pokémon file is read or imported.
    func initialize() async {
        guard !isBusy, !hasRemoteSave, !hasUnsavedChanges, alias != nil, revision == 0, let store else { return }
        let candidate = CompanionState()
        inFlight = CloudSaveCommand(expectedRevision: 0, requestID: UUID(), operation: "save", state: candidate, rules: .init(growthDifficulty: store.growthDifficulty, shopDifficulty: store.shopDifficulty))
        store.replaceCloudState(candidate, writable: false)
        hasUnsavedChanges = true
        await drain(operation: generation)
    }

    private func enqueue(_ state: CompanionState) {
        pending = state
        hasUnsavedChanges = true
        schedulePending()
    }

    private func schedulePending() {
        guard pending != nil, worker == nil, !isBusy, !canRetry else { return }
        let operation = generation
        worker = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await self?.drain(operation: operation)
        }
    }

    private func drain(operation: UUID) async {
        guard operation == generation, let repository, let authentication else { return }
        isBusy = true
        defer { if operation == generation { isBusy = false; worker = nil } }
        do {
            while inFlight != nil || pending != nil {
                if inFlight == nil, let next = pending {
                    pending = nil
                    inFlight = .init(expectedRevision: revision, requestID: UUID(), operation: "save", state: next, rules: .init(growthDifficulty: store?.growthDifficulty ?? 1, shopDifficulty: store?.shopDifficulty ?? 1))
                }
                guard let command = inFlight else { break }
                guard authentication.userID == ownerID else { throw CloudError.authentication }
                let token = try await authentication.accessToken()
                guard operation == generation, authentication.userID == ownerID else { throw CloudError.authentication }
                let receipt = try await repository.write(command, token: token)
                guard operation == generation else { return }
                guard receipt.ownerID == ownerID, receipt.requestID == command.requestID,
                      receipt.revision == command.expectedRevision + 1 else { throw CloudError.invalidResponse }
                revision = receipt.revision
                inFlight = nil
                hasRemoteSave = true
                canRetry = false
            }
            hasUnsavedChanges = false
            store?.setCloudWritable(true)
            status = "서버 저장 완료 · 버전 \(revision)"
        } catch {
            guard operation == generation else { return }
            store?.setCloudWritable(false)
            canRetry = (error as? CloudError) != .conflict
            status = error.localizedDescription
            if let failure = error as? CloudError, case .saveDeferred(let seconds) = failure {
                scheduleDeferredRetry(after: seconds, operation: operation)
            }
        }
    }

    private func scheduleDeferredRetry(after seconds: Int, operation: UUID) {
        retryWorker?.cancel()
        retryWorker = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, min(3600, seconds)))) } catch { return }
            guard let self, self.generation == operation else { return }
            self.retryWorker = nil
            await self.retry()
        }
    }

    func retry() async {
        guard !isBusy, canRetry else { return }
        retryWorker?.cancel(); retryWorker = nil
        canRetry = false
        await drain(operation: generation)
    }

    func reconnectAndRetry() async {
        guard !isBusy, canRetry, let authentication else { return }
        isBusy = true
        do {
            try await authentication.restore()
            guard authentication.userID == ownerID else { throw CloudError.authentication }
            isBusy = false
            await retry()
        } catch {
            status = error.localizedDescription
            isBusy = false
        }
    }

    /// Called only after the user explicitly accepts discarding unacknowledged changes.
    func discardAndReload() async {
        guard !isBusy else { return }
        generation = UUID()
        retryWorker?.cancel(); retryWorker = nil
        worker?.cancel(); worker = nil
        pending = nil; inFlight = nil
        hasUnsavedChanges = false; canRetry = false
        await reload()
    }

    func disconnect() async {
        guard !isBusy, !hasUnsavedChanges else { return }
        isBusy = true
        defer { isBusy = false }
        store?.setCloudWritable(false)
        do { try await authentication?.signOut() }
        catch {
            store?.setCloudWritable(hasRemoteSave)
            status = error.localizedDescription
            return
        }
        generation = UUID()
        retryWorker?.cancel(); retryWorker = nil
        worker?.cancel(); worker = nil
        store?.replaceCloudState(CompanionState(), writable: false)
        alias = nil; revision = 0; hasRemoteSave = false
        ownerID = nil
        status = "로그아웃됨. 서버 데이터는 유지됩니다."
    }
}
