import AppKit
import SwiftUI

@MainActor
final class EncounterPanel: NSObject, NSWindowDelegate {
    private let controller: EncounterController
    private let controls: NSPanel
    private lazy var stage = DesktopBattleStage(settings: { [weak self] in self?.showControls() }, hide: { [weak self] in self?.hide() })
    init(account: CloudCompanionController, serviceURL: URL) {
        controller = EncounterController(repository: EncounterRepository(serviceURL: serviceURL), token: { try await account.encounterToken() })
        controls = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 472, height: 490),
                           styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        controls.title = "링크 펫 · 연결과 기술"
        controls.isReleasedWhenClosed = false
        controls.level = .floating
        let host = NSHostingView(rootView: EncounterPanelView(controller: controller))
        host.sizingOptions = []; controls.contentView = host; controls.center()
        stage.observe(account: account,controller: controller,settings: { [weak self] in self?.showControls() },hide: { [weak self] in self?.hide() })
    }
    func open() { stage.open(); controller.start(); if controller.room == nil { showControls() } }
    private func showControls() { controls.makeKeyAndOrderFront(nil) }
    private func hide() { controller.stop(); stage.stop(); controls.orderOut(nil) }
}

@MainActor
struct EncounterPanelView: View {
    @Bindable var controller: EncounterController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.status).font(.caption).foregroundStyle(controller.connected ? .secondary : .primary)
                .frame(height: 28, alignment: .leading)
            if let room = controller.room, !room.closed {
                HStack {
                    if let code = room.inviteCode {
                        Text(code).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Button("복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                    } else { Text("연결된 방 · 초대는 생성 후 30분간 유효").font(.caption) }
                    Spacer()
                    Button("나가기") { Task { await controller.perform("leave") } }
                }
                if !controller.choices.isEmpty {
                    ScrollView(.horizontal) {
                        LazyHStack {
                            ForEach(controller.choices, id: \.id) { pokemon in
                                Button(pokemon.title) { Task { await controller.perform("select", individualID: pokemon.id) } }
                            }
                        }
                    }.frame(height: 34)
                }
            } else {
                HStack {
                    Button("초대 만들기") { Task { await controller.perform("create") } }
                    TextField("32자리 초대코드", text: $controller.invitation).textFieldStyle(.roundedBorder)
                    Button("참여") { Task { await controller.perform("join") } }.disabled(controller.invitation.count != 32)
                }
            }
            if !controller.skills.isEmpty {
                Text("현재 레벨의 기술 · 블랙2·화이트2").font(.caption).bold()
                ForEach(controller.skills) { move in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(move.nameKo).font(.callout).bold()
                            Text(move.summary).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("시전") { Task { await controller.attack(move) } }
                            .disabled(!controller.connected || controller.room?.members.filter({ $0.pokemon != nil }).count != 2)
                    }.help(move.referenceDetails)
                }
            }
            Text("내 서버 포켓몬만 선택할 수 있어요. 선택 정보만 공유되며 성장 데이터는 바뀌지 않습니다.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16).frame(width: 472, height: 490, alignment: .topLeading)
        .disabled(controller.busy)
    }
}
