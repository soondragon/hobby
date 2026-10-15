import SwiftUI

struct EncounterPetView: View {
    let state: DesktopBattleState
    let isSelf: Bool
    let settings: () -> Void
    let hide: () -> Void
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.playbacks.isEmpty || state.frozenProgress != nil)) { clock in
            let member = state.members.first(where: { $0.isSelf == isSelf })
            let active = state.playbacks.last(where: { let p = state.frozenProgress ?? $0.progress(at: clock.date); return $0.event.actorIsSelf == isSelf && p >= 0 && p <= 1 })
                ?? state.playbacks.last(where: { let p = state.frozenProgress ?? $0.progress(at: clock.date); return p >= 0 && p <= 1 })
            let ownAttack = active?.event.actorIsSelf == isSelf
            let phase = active.map { state.frozenProgress ?? $0.progress(at: clock.date) } ?? -1
            VStack(spacing: 12) {
                EncounterSpeechBubble(member: member, placeholder: isSelf ? "내 포켓몬 선택" : "상대 연결 대기",
                                      message: ownAttack ? active.map { $0.event.moveName + "!" } : nil)
                EncounterSprite(pokemon: member?.pokemon, back: isSelf)
                    .frame(width: isSelf ? 180 : 158, height: 180)
                    .offset(x: motion(phase, attacking: ownAttack))
                    .opacity(!ownAttack && phase > 0.7 && phase < 0.94 ? 0.55 + 0.45 * abs(sin(phase * 85)) : 1)
            }
        }
        .padding(12).frame(width: 240, height: 290)
        .background(Color.clear)
        .contextMenu {
            Button("초대·포켓몬 선택·기술", action: settings)
            Button("플로팅 펫 숨기기", action: hide)
        }
    }
    private func motion(_ progress: Double, attacking: Bool) -> Double {
        guard progress >= 0, progress <= 1 else { return 0 }
        if attacking { return sin(min(1, progress / 0.3) * .pi) * (isSelf ? 12 : -12) }
        return progress > 0.7 ? sin(progress * 90) * 5 * (1-progress) : 0
    }
}
