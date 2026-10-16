#if DEBUG
import AppKit
import SwiftUI
import Observation

@MainActor
enum EncounterPreviewBootstrap {
    private static var stage: DesktopBattleStage?
    private static var inspector: NSWindow?
    private static var settings: NSWindow?
    static func windowIfRequested() -> NSWindow? {
        guard Bundle.main.object(forInfoDictionaryKey: "EncounterPreviewOnly") as? Bool == true,
              let url = Bundle.main.url(forResource: "MoveCatalog",withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(PreviewMoveCatalog.self,from: data) else { return nil }
        NSApp.setActivationPolicy(.regular)
        let model = PreviewSkillModel(catalog: catalog)
        let controls = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 650,height: 520),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        controls.title = "데스크톱 배틀 · 로컬 기술 데모"
        controls.isReleasedWhenClosed = false
        let battle = DesktopBattleStage(settings: { controls.makeKeyAndOrderFront(nil) },hide: { stage?.stop() })
        stage = battle
        let check = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 450,height: 402),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        check.title = "기술 이펙트 검수 · 실제 렌더링 · 로컬 샘플"
        check.isReleasedWhenClosed = false
        check.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        let scene = NSHostingView(rootView: BattleInspectionView(state: battle.state))
        scene.sizingOptions = [];check.contentView = scene;check.center();inspector = check
        let host = NSHostingView(rootView: PreviewSkillControls(model: model,stage: battle,inspect: { check.makeKeyAndOrderFront(nil) }))
        host.sizingOptions = [];controls.contentView = host;controls.center();settings = controls
        battle.state.members = model.members
        battle.open(); controls.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controls
    }
}

private struct PreviewMoveCatalog: Decodable {
    struct Species: Decodable {
        struct Learn: Decodable { let moveID: Int;let methodID: Int;let level: Int }
        let nameKo: String
        let learnset: [Learn]
    }
    let moves: [String:EncounterMove]
    let species: [String:Species]
    func skills(speciesID: Int,level: Int) -> [EncounterMove] {
        var levels: [Int:Int] = [:]
        for row in species[String(speciesID)]?.learnset ?? [] where row.methodID == 1 && row.level <= level {
            levels[row.moveID] = min(levels[row.moveID] ?? 1000,row.level)
        }
        let sorted = levels.keys.sorted {
            if levels[$0] != levels[$1] { return levels[$0]! < levels[$1]! }
            return (moves[String($0)]?.name ?? "") < (moves[String($1)]?.name ?? "")
        }
        return sorted.suffix(4).compactMap { moves[String($0)] }
    }
}

@MainActor @Observable
private final class PreviewSkillModel {
    let catalog: PreviewMoveCatalog
    var ownSpecies = 6
    var opponentSpecies = 9
    var level = 60
    init(catalog: PreviewMoveCatalog) { self.catalog = catalog }
    var members: [EncounterMember] { [
        .init(isSelf: true,alias: "trainer-one",pokemon: .init(speciesID: ownSpecies,level: level,isShiny: false,unownForm: nil)),
        .init(isSelf: false,alias: "trainer-two",pokemon: .init(speciesID: opponentSpecies,level: level,isShiny: false,unownForm: nil))
    ] }
}

private struct PreviewSkillControls: View {
    @Bindable var model: PreviewSkillModel
    let stage: DesktopBattleStage
    let inspect: () -> Void
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("로컬 연출 데모 · 실제 계정·서버 성장 데이터와 무관").font(.headline)
            Text("PokéAPI · 블랙2·화이트2 · 각 레벨에서 자연 습득한 최근 기술 4개").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("내 번호",value: $model.ownSpecies,format: .number).frame(width: 65)
                TextField("상대 번호",value: $model.opponentSpecies,format: .number).frame(width: 65)
                Stepper("Lv.\(model.level)",value: $model.level,in: 1...100)
                Button("포켓몬 적용") {
                    guard (1...649).contains(model.ownSpecies),(1...649).contains(model.opponentSpecies) else { return }
                    stage.state.members = model.members
                }
            }
            HStack(alignment: .top,spacing: 24) {
                skills(species: model.ownSpecies,isSelf: true)
                skills(species: model.opponentSpecies,isSelf: false)
            }
            Divider()
            HStack {
                Button("동시 시전") { counterAttack() }
                Button("예시 정지 화면") { stage.state.frozenProgress = 0.52;stage.state.playbacks = [];
                    if let move = model.catalog.skills(speciesID: model.ownSpecies,level: model.level).first(where: { $0.damageClass == "special" }) { stage.demo(move: move,actorIsSelf: true) };inspect() }
                Button("실시간 재생") { stage.resumeDemo() }
                Button("검수 화면") { inspect() }
            }
            Text("기술 연출·피격 모션 데모입니다. HP·승패·보상은 계산하지 않습니다.").font(.caption)
            Spacer()
        }.padding(20).frame(width: 650,height: 520)
    }
    private func skills(species: Int,isSelf: Bool) -> some View {
        VStack(alignment: .leading,spacing: 10) {
            Text((isSelf ? "내 " : "상대 ") + (model.catalog.species[String(species)]?.nameKo ?? "번호 확인")).bold()
            ForEach(model.catalog.skills(speciesID: species,level: model.level)) { move in
                VStack(alignment: .leading,spacing: 3) {
                    HStack { Text(move.nameKo).bold();Spacer();Button("시전") { stage.demo(move: move,actorIsSelf: isSelf) } }
                    Text(move.summary).font(.caption2).foregroundStyle(.secondary)
                }.help(move.referenceDetails)
            }
        }.frame(maxWidth: .infinity)
    }
    private func counterAttack() {
        if stage.state.frozenProgress != nil { stage.state.playbacks = [] }
        for (species,isSelf) in [(model.ownSpecies,true),(model.opponentSpecies,false)] {
            let moves = model.catalog.skills(speciesID: species,level: model.level)
            if let move = moves.first(where: { $0.damageClass == "special" }) ?? moves.first {
                stage.demo(move: move,actorIsSelf: isSelf)
            }
        }
    }
}

private struct BattleInspectionView: View {
    let state: DesktopBattleState
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 450,geometry.size.height / 402)
            ZStack(alignment: .topLeading) {
                EncounterBattleView(members: state.members)
                BattleEffects(playbacks: state.playbacks,ownAnchor: CGPoint(x: 146,y: 262),opponentAnchor: CGPoint(x: 304,y: 157),frozenProgress: state.frozenProgress)
                    .frame(width: 450,height: 402)
            }
            .frame(width: 450,height: 402)
            .scaleEffect(scale,anchor: .topLeading)
        }
        .background(Color.white)
    }
}
#endif
