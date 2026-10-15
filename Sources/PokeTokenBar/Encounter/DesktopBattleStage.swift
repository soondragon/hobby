import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class DesktopBattleState {
    var members: [EncounterMember] = []
    var playbacks: [SkillPlayback] = []
    var ownAnchor = CGPoint.zero
    var opponentAnchor = CGPoint.zero
    var canvasSize = CGSize(width: 1280, height: 720)
    var frozenProgress: Double?
}

/// Two draggable pet windows plus a mouse-transparent effect layer spanning the active monitor.
@MainActor
final class DesktopBattleStage {
    let state = DesktopBattleState()
    private let own: NSPanel
    private let opponent: NSPanel
    private let effects: NSPanel
    private var timer: Task<Void, Never>?
    private var seen = Set<Int>()
    private var roomID: UUID?
    private var demoID = 0

    init(settings: @escaping () -> Void, hide: @escaping () -> Void) {
        own = EncounterWindowStyle.floatingPanel(size: NSSize(width: 240, height: 290))
        opponent = EncounterWindowStyle.floatingPanel(size: NSSize(width: 240, height: 290))
        effects = EncounterWindowStyle.floatingPanel()
        own.title = "내 배틀 포켓몬"; opponent.title = "상대 배틀 포켓몬"; effects.title = "데스크톱 기술 이펙트"
        effects.ignoresMouseEvents = true
        effects.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let a = NSHostingView(rootView: EncounterPetView(state: state,isSelf: true,settings: settings,hide: hide))
        let b = NSHostingView(rootView: EncounterPetView(state: state,isSelf: false,settings: settings,hide: hide))
        let c = NSHostingView(rootView: DesktopEffectRoot(state: state))
        a.sizingOptions = []; b.sizingOptions = []; c.sizingOptions = []
        own.contentView = a; opponent.contentView = b; effects.contentView = c
    }
    func observe(account: CloudCompanionController, controller: EncounterController, settings: @escaping () -> Void, hide: @escaping () -> Void) {
        let host = NSHostingView(rootView: EncounterStageBridge(state: state, account: account, controller: controller,
            settings: settings, hide: hide, update: { [weak self] in self?.synchronize($0) }))
        host.sizingOptions = []; own.contentView = host
    }
    func open() {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        state.canvasSize = frame.size
        effects.setFrame(frame, display: true)
        own.setFrameOrigin(NSPoint(x: frame.minX+48,y: frame.minY+40))
        opponent.setFrameOrigin(NSPoint(x: frame.maxX-300,y: frame.maxY-330))
        own.orderFrontRegardless(); opponent.orderFrontRegardless(); effects.orderFrontRegardless()
        updateAnchors()
    }
    func stop() {
        timer?.cancel(); timer = nil; state.playbacks = []; state.frozenProgress = nil
        own.orderOut(nil); opponent.orderOut(nil); effects.orderOut(nil)
    }
    func synchronize(_ room: EncounterRoom?) {
        if roomID != room?.id { seen = []; roomID = room?.id; state.playbacks = [] }
        state.members = room?.members ?? []
        guard let room, !room.closed, let serverTime = room.serverTime else { state.playbacks = []; return }
        for event in room.events ?? [] where !seen.contains(event.id) {
            seen.insert(event.id)
            let delta = event.startsAt-serverTime
            guard delta > -SkillPlayback.duration, delta <= 5 else { continue }
            state.playbacks.append(.init(event: event,start: Date().addingTimeInterval(delta)))
        }
        if seen.count > 64 { seen = Set(seen.sorted().suffix(32)) }
        state.playbacks = Array(state.playbacks.suffix(4))
        animateWhileNeeded()
    }
    func demo(move: EncounterMove, actorIsSelf: Bool) {
        demoID += 1
        state.playbacks.append(.init(event: .init(id: demoID,actorIsSelf: actorIsSelf,moveID: move.id,moveName: move.nameKo,
            type: move.type,damageClass: move.damageClass,target: move.target,startsAt: Date().timeIntervalSince1970+0.25), start: Date().addingTimeInterval(0.25)))
        state.playbacks = Array(state.playbacks.suffix(4))
        animateWhileNeeded()
    }
    func resumeDemo() {
        state.frozenProgress = nil
        state.playbacks = state.playbacks.map { .init(event: $0.event,start: Date().addingTimeInterval(0.25)) }
        animateWhileNeeded()
    }
    private func animateWhileNeeded() {
        if state.frozenProgress != nil { updateAnchors();timer?.cancel();timer = nil;return }
        guard timer == nil, !state.playbacks.isEmpty else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.state.frozenProgress == nil { self.state.playbacks.removeAll { $0.progress(at: Date()) > 1 } }
                if self.state.playbacks.isEmpty { self.timer = nil; return }
                self.updateAnchors()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    private func updateAnchors() {
        let frame = effects.frame
        state.ownAnchor = CGPoint(x: own.frame.minX+155-frame.minX,y: frame.maxY-(own.frame.maxY-150))
        state.opponentAnchor = CGPoint(x: opponent.frame.minX+90-frame.minX,y: frame.maxY-(opponent.frame.maxY-150))
    }
}

private struct DesktopEffectRoot: View {
    let state: DesktopBattleState
    var body: some View {
        BattleEffects(playbacks: state.playbacks,ownAnchor: state.ownAnchor,opponentAnchor: state.opponentAnchor,frozenProgress: state.frozenProgress)
            .background(Color.clear)
    }
}
private struct EncounterStageBridge: View {
    let state: DesktopBattleState
    let account: CloudCompanionController
    let controller: EncounterController
    let settings: () -> Void
    let hide: () -> Void
    let update: (EncounterRoom?) -> Void
    var body: some View {
        EncounterPetView(state: state,isSelf: true,settings: settings,hide: hide)
            .onAppear { update(controller.room) }
            .onChange(of: controller.room?.revision) { _,_ in update(controller.room) }
            .onChange(of: controller.room?.members) { _,_ in update(controller.room) }
            .onChange(of: account.ownerID) { _,_ in controller.stop(clear: true); update(nil); hide() }
    }
}
