import Foundation

/// Shared canonical identity and reference traits; individual Pokémon never override these values.
struct MoveDefinition: Decodable, Sendable {
    struct Traits: Decodable, Sendable {
        struct StatChange: Decodable, Sendable { let stat: String; let change: Int }
        let ailment: String
        let min_hits: Int?
        let max_hits: Int?
        let min_turns: Int?
        let max_turns: Int?
        let drain: Int?
        let healing: Int?
        let crit_rate: Int?
        let flinch_chance: Int?
        let stat_chance: Int?
        let ailment_chance: Int?
        let statChanges: [StatChange]
    }
    struct Presentation: Decodable, Sendable {
        let style: Style
        let color: String
    }
    enum Style: String, Decodable, Sendable {
        case projectile, stream, vortex, burst, wave, bolt, strike, weather, shield, boost, pulse, heal, drain, contact
    }
    let id: Int
    let nameKo: String
    let type: String
    let damageClass: String
    let target: String
    let power: Int?
    let accuracy: Int?
    let pp: Int
    let description: String
    let traits: Traits
    let presentation: Presentation
    var targetsUser: Bool { ["user","users-field","user-and-allies","all-allies"].contains(target) }
    var details: String {
        var lines = ["#\(id) \(nameKo)",description]
        if traits.ailment != "none" { lines.append("\(traits.ailment) · " + ((traits.ailment_chance ?? 0) > 0 ? "추가 확률 \(traits.ailment_chance!)%" : "추가 확률 표기 없음")) }
        if let hits = traits.max_hits, hits > 1 { lines.append("타격 \(traits.min_hits ?? hits)–\(hits)") }
        if let drain = traits.drain, drain != 0 { lines.append("흡수(+)/반동(-) \(drain)%") }
        if let healing = traits.healing, healing > 0 { lines.append("회복 \(healing)%") }
        if let turns = traits.max_turns { lines.append("지속 \(traits.min_turns ?? turns)–\(turns)턴") }
        if let chance = traits.flinch_chance, chance > 0 { lines.append("풀죽음 추가 확률 \(chance)%") }
        if let critical = traits.crit_rate, critical > 0 { lines.append("급소 보정 +\(critical)") }
        lines += traits.statChanges.map { "\($0.stat) \($0.change > 0 ? "+" : "")\($0.change)" }
        lines.append("특성은 원본 메타데이터 참고용이며 상태이상·HP 결과는 계산하지 않습니다.")
        return lines.joined(separator: "\n")
    }
}

enum MoveDefinitions {
    private struct Catalog: Decodable { let moves: [String:MoveDefinition] }
    static let all: [Int:MoveDefinition] = {
        let installed = Bundle.main.url(forResource: "MoveDefinitions",withExtension: "json")
        guard let url = installed ?? Bundle.module.url(forResource: "MoveDefinitions",withExtension: "json"),
              let data = try? Data(contentsOf: url),let catalog = try? JSONDecoder().decode(Catalog.self,from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.moves.values.map { ($0.id,$0) })
    }()
    static func find(_ id: Int) -> MoveDefinition? { all[id] }
}
