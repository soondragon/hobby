import SwiftUI

/// Blue-style composition; display only, with no simulated HP or battle commands.
struct EncounterBattleView: View {
    let members: [EncounterMember]
    private var own: EncounterMember? { members.first(where: \.isSelf) }
    private var opponent: EncounterMember? { members.first(where: { !$0.isSelf }) }
    var body: some View {
        ZStack {
            EncounterSpeechBubble(member: opponent, placeholder: "상대를 기다리는 중")
                .position(x: 334, y: 50)
            EncounterSprite(pokemon: opponent?.pokemon, back: false)
                .frame(width: 146, height: 146).position(x: 332, y: 157)
            EncounterSpeechBubble(member: own, placeholder: "내 포켓몬 선택")
                .position(x: 111, y: 161)
            EncounterSprite(pokemon: own?.pokemon, back: true)
                .frame(width: 180, height: 180).position(x: 114, y: 274)
        }
        .frame(width: 450, height: 370).background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("내 포켓몬은 왼쪽 아래 뒷모습, 상대 포켓몬은 오른쪽 위 앞모습")
    }
}

struct EncounterSprite: View {
    let pokemon: EncounterPokemon?
    let back: Bool
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 4)
            } else if pokemon == nil {
                Image(systemName: "circle.dashed").font(.system(size: 36)).opacity(0.25)
            } else if failed { Text("이미지 연결 실패").font(.caption) }
            else { ProgressView().controlSize(.small) }
        }
        .accessibilityLabel(pokemon.map { "\($0.title) \(back ? "뒷모습" : "앞모습")" } ?? "선택 대기")
        .task(id: pokemon) {
            image = nil; failed = false
            guard let pokemon else { return }
            let form = pokemon.unownForm.flatMap(UnownForm.init(rawValue:))
            let data = await SpriteStore.shared.data(speciesID: pokemon.speciesID, animated: false,
                                                       shiny: pokemon.isShiny, unownForm: form, back: back)
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:)); failed = image == nil
        }
    }
}
