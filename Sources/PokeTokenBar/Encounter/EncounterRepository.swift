import Foundation

struct EncounterPokemon: Codable, Sendable, Equatable {
    var id: String?
    let speciesID: Int
    let level: Int
    let isShiny: Bool
    let unownForm: String?
    var title: String { "#\(speciesID)  Lv.\(level)\(isShiny ? " ✦" : "")" }
}
struct EncounterMember: Decodable, Sendable {
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
    func roster(token: String) async throws -> EncounterRoster
    func command(_ command: EncounterCommand, token: String) async throws -> EncounterRoom
}
struct EncounterRepository: EncounterServing {
    let serviceURL: URL
    private let transport = CloudTransport()
    func roster(token: String) async throws -> EncounterRoster {
        try await transport.request(EncounterRoster.self, url: serviceURL.appendingPathComponent("api/encounter/roster"), token: token)
    }
    func command(_ command: EncounterCommand, token: String) async throws -> EncounterRoom {
        try await transport.request(EncounterRoom.self, url: serviceURL.appendingPathComponent("api/encounter"),
                                    method: "POST", token: token, body: JSONEncoder().encode(command))
    }
}
