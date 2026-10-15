import Foundation
import Observation

@MainActor @Observable
final class EncounterController {
    private(set) var room: EncounterRoom?
    private(set) var choices: [EncounterPokemon] = []
    private(set) var busy = false
    private(set) var status = "서버 포켓몬을 불러오는 중…"
    private(set) var connected = false
    var invitation = ""
    private let repository: any EncounterServing
    private let token: @MainActor () async throws -> String
    private var generation = UUID()
    private var polling: Task<Void, Never>?

    init(repository: any EncounterServing, token: @escaping @MainActor () async throws -> String) {
        self.repository = repository; self.token = token
    }
    func start() {
        guard polling == nil else { return }
        let operation = generation
        polling = Task { [weak self] in
            var delay = 2
            var iteration = 0
            while !Task.isCancelled {
                guard let self, self.generation == operation else { return }
                if !self.busy {
                    await self.refresh(includeRoster: iteration % 15 == 0)
                    iteration += 1
                    delay = self.connected ? 2 : min(30, delay * 2)
                }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }
    func stop(clear: Bool = false) {
        generation = UUID(); polling?.cancel(); polling = nil
        busy = false; connected = false
        if clear { room = nil; choices = []; invitation = ""; status = "다시 로그인해 주세요." }
    }
    func refresh(includeRoster: Bool = true) async {
        guard !busy else { return }
        busy = true
        let operation = generation
        defer { if generation == operation { busy = false } }
        do {
            if includeRoster {
                let value = try await repository.roster(token: token())
                guard generation == operation else { return }
                guard value.choices.count <= 10001, value.choices.allSatisfy({ valid($0) && $0.id != nil }) else { throw CloudError.invalidResponse }
                choices = value.choices
                if room == nil, let restored = value.room { try accept(restored) }
            }
            if let current = room {
                let updated = try await repository.command(.init(action: "read", roomID: current.id), token: token())
                guard generation == operation else { return }
                try accept(updated)
            }
            connected = true
            status = room?.closed == true ? "만남이 종료됐습니다. 새 초대를 만들 수 있어요." : choices.isEmpty ? "서버에 소유한 포켓몬이 없습니다. 먼저 포켓몬을 성장시켜 주세요." : "내 포켓몬을 선택해 상대에게 보여 주세요."
        } catch { if generation == operation { connected = false; status = "연결을 확인해 주세요. 재연결 중…" } }
    }
    func perform(_ action: String, individualID: String? = nil) async {
        guard !busy else { return }
        busy = true
        let operation = generation
        defer { if generation == operation { busy = false } }
        do {
            let command: EncounterCommand
            switch action {
            case "create": command = .init(action: action)
            case "join": command = .init(action: action, code: invitation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            default:
                guard let room, !room.closed else { throw CloudError.conflict }
                command = .init(action: action, roomID: room.id, expectedRevision: room.revision, individualID: individualID)
            }
            let updated = try await repository.command(command, token: token())
            guard generation == operation else { return }
            try accept(updated); connected = true
            status = updated.closed ? "만남을 종료했습니다." : "연결됨 · 선택한 포켓몬만 공유합니다."
        } catch {
            guard generation == operation else { return }
            status = "요청하지 못했습니다. 초대코드·소유권·만료 여부를 확인하고 다시 시도해 주세요."
            if case CloudError.authentication = error { stop(clear: true) }
        }
    }
    private func valid(_ pokemon: EncounterPokemon) -> Bool {
        (1...649).contains(pokemon.speciesID) && (1...100).contains(pokemon.level)
    }
    private func accept(_ updated: EncounterRoom) throws {
        guard updated.revision > 0, updated.members.count <= 2,
              updated.members.filter(\.isSelf).count == 1,
              updated.members.allSatisfy({ !$0.alias.isEmpty && $0.alias.count <= 39 && ($0.pokemon.map(valid) ?? true) }) else { throw CloudError.invalidResponse }
        var value = updated
        if updated.id == room?.id { value.inviteCode = updated.inviteCode ?? room?.inviteCode }
        room = value
    }
}
