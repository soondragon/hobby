import Foundation

struct EncounterMove: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let nameKo: String
    let type: String
    let typeKo: String
    let damageClass: String
    let power: Int?
    let accuracy: Int?
    let pp: Int
    let priority: Int
    let target: String
    let description: String
    var summary: String { "\(typeKo) · 위력 \(power.map(String.init) ?? "—") · 명중 \(accuracy.map(String.init) ?? "—") · PP \(pp)" }
}
struct EncounterSkillList: Decodable, Sendable { let moves: [EncounterMove] }
struct EncounterSkillCommand: Encodable, Sendable {
    let roomID: UUID
    let expectedRevision: Int
    let requestID: UUID
    let moveID: Int
}
struct EncounterSkillEvent: Decodable, Sendable, Equatable, Identifiable {
    let id: Int
    let actorIsSelf: Bool
    let moveID: Int
    let moveName: String
    let type: String
    let damageClass: String
    let target: String
    let startsAt: Double
    var targetsUser: Bool { ["user", "users-field", "user-and-allies", "all-allies"].contains(target) }
}
struct SkillPlayback: Identifiable, Equatable {
    let event: EncounterSkillEvent
    let start: Date
    var id: Int { event.id }
    static let duration = 2.2
    func progress(at date: Date) -> Double { date.timeIntervalSince(start) / Self.duration }
}
