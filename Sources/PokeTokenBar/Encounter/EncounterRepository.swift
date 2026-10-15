import Foundation

struct EncounterPokemon: Codable, Sendable, Equatable {
    var id: String?
    let speciesID: Int
    let level: Int
    let isShiny: Bool
    let unownForm: String?
    var title: String { "#\(speciesID)  Lv.\(level)\(isShiny ? " ✦" : "")" }
}
struct EncounterMember: Decodable, Sendable, Equatable {
    let isSelf: Bool
    let alias: String
    let pokemon: EncounterPokemon?
}
struct EncounterRoom: Decodable, Sendable {
    let id: UUID
    let revision: Int
    let closed: Bool
    let members: [EncounterMember]
    var inviteCode: String?
    var serverTime: Double? = nil
    var events: [EncounterSkillEvent]? = nil
}
struct EncounterRoster: Decodable, Sendable {
    let choices: [EncounterPokemon]
    let room: EncounterRoom?
}
struct EncounterCommand: Encodable, Sendable {
    let action: String
    var code: String? = nil
    var roomID: UUID? = nil
    var expectedRevision: Int? = nil
    var individualID: String? = nil
}
protocol EncounterServing: Sendable {
    func skills(roomID: UUID, token: String) async throws -> [EncounterMove]
    func attack(_ command: EncounterSkillCommand, token: String) async throws -> EncounterRoom
    func roster(token: String) async throws -> EncounterRoster
    func command(_ command: EncounterCommand, token: String) async throws -> EncounterRoom
}
extension EncounterServing {
    func skills(roomID: UUID, token: String) async throws -> [EncounterMove] { [] }
    func attack(_ command: EncounterSkillCommand, token: String) async throws -> EncounterRoom { throw CloudError.configuration }
}
struct EncounterRepository: EncounterServing {
    let serviceURL: URL
    private let transport = CloudTransport()
    func skills(roomID: UUID, token: String) async throws -> [EncounterMove] {
        try await transport.request(EncounterSkillList.self, url: serviceURL.appendingPathComponent("api/encounter/\(roomID.uuidString)/moves"), token: token).moves
    }
    func attack(_ command: EncounterSkillCommand, token: String) async throws -> EncounterRoom {
        try await transport.request(EncounterRoom.self, url: serviceURL.appendingPathComponent("api/encounter/attack"), method: "POST", token: token, body: JSONEncoder().encode(command))
    }
    func roster(token: String) async throws -> EncounterRoster {
        try await transport.request(EncounterRoster.self, url: serviceURL.appendingPathComponent("api/encounter/roster"), token: token)
    }
    func command(_ command: EncounterCommand, token: String) async throws -> EncounterRoom {
        try await transport.request(EncounterRoom.self, url: serviceURL.appendingPathComponent("api/encounter"),
                                    method: "POST", token: token, body: JSONEncoder().encode(command))
    }
}
