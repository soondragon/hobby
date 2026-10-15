import SwiftUI

/// Blue-style composition; display only, with no simulated HP or battle commands.
struct EncounterBattleView: View {
    let members: [EncounterMember]
    private var own: EncounterMember? { members.first(where: \.isSelf) }
    private var opponent: EncounterMember? { members.first(where: { !$0.isSelf }) }
    private let ink = Color(red: 0.12, green: 0.20, blue: 0.36)
    var body: some View {
        ZStack {
            Color(red: 0.86, green: 0.90, blue: 0.96)
            VStack {
                HStack { Text("LINK ENCOUNTER"); Spacer(); Text("BLUE / 02") }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Spacer()
                HStack { Text("DISPLAY ONLY"); Spacer(); Text("두 트레이너의 만남") }
                    .font(.system(size: 9, design: .monospaced))
            }.padding(14)
            label(opponent, placeholder: "상대를 기다리는 중").position(x: 115, y: 65)
            EncounterSprite(pokemon: opponent?.pokemon, back: false).frame(width: 132, height: 132).position(x: 330, y: 106)
            Path { p in p.move(to: .init(x: 269, y: 162)); p.addLine(to: .init(x: 397, y: 162)) }.stroke(ink.opacity(0.35), lineWidth: 2)
            EncounterSprite(pokemon: own?.pokemon, back: true).frame(width: 164, height: 164).position(x: 108, y: 202)
            label(own, placeholder: "내 포켓몬 선택").position(x: 318, y: 216)
        }
        .foregroundStyle(ink).frame(width: 440, height: 300)
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 3))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("내 포켓몬은 왼쪽 아래 뒷모습, 상대 포켓몬은 오른쪽 위 앞모습")
    }
    private func label(_ member: EncounterMember?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(member.map { "@" + $0.alias } ?? placeholder).font(.system(size: 13, weight: .bold, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
            Text(member?.pokemon?.title ?? "포켓몬 선택 대기")
                .font(.system(size: 12, design: .monospaced))
        }.frame(width: 180, alignment: .leading)
    }
}

private struct EncounterSprite: View {
    let pokemon: EncounterPokemon?
    let back: Bool
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit().saturation(0)
                    .colorMultiply(Color(red: 0.35, green: 0.46, blue: 0.68))
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
