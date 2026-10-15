import AppKit
import SwiftUI

@MainActor
final class EncounterPanel: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let controller: EncounterController
    private let controls: NSPanel
    init(account: CloudCompanionController, serviceURL: URL) {
        controller = EncounterController(repository: EncounterRepository(serviceURL: serviceURL), token: { try await account.encounterToken() })
        panel = EncounterWindowStyle.floatingPanel()
        controls = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 472, height: 280),
                           styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "포켓몬 · 링크 플로팅 펫"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        controls.title = "링크 펫 · 연결과 포켓몬 선택"
        controls.isReleasedWhenClosed = false
        controls.level = .floating
        let controlHost = NSHostingView(rootView: EncounterPanelView(controller: controller))
        controlHost.sizingOptions = []
        controls.contentView = controlHost
        controls.center()
        let host = NSHostingView(rootView: EncounterAccountBoundary(account: account, controller: controller,
            settings: { [weak self] in self?.showControls() },
            close: { [weak self] in self?.hide(clear: true) },
            hide: { [weak self] in self?.hide() }))
        host.sizingOptions = []
        panel.contentView = host
        panel.center()
    }
    func open() {
        panel.makeKeyAndOrderFront(nil); controller.start()
        if controller.room == nil { showControls() }
    }
    private func showControls() {
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            controls.setFrameOrigin(NSPoint(x: min(max(panel.frame.maxX + 12, visible.minX), visible.maxX - controls.frame.width),
                                            y: min(max(panel.frame.minY, visible.minY), visible.maxY - controls.frame.height)))
        }
        controls.makeKeyAndOrderFront(nil)
    }
    private func hide(clear: Bool = false) {
        controller.stop(clear: clear); panel.orderOut(nil); controls.orderOut(nil)
    }
    func windowWillClose(_ notification: Notification) { hide() }
}

private struct EncounterAccountBoundary: View {
    let account: CloudCompanionController
    let controller: EncounterController
    let settings: () -> Void
    let close: () -> Void
    let hide: () -> Void
    var body: some View {
        EncounterDesktopView(members: controller.room?.members ?? [], settings: settings, hide: hide)
            .onChange(of: account.ownerID) { _, _ in controller.stop(clear: true); close() }
    }
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
            Text("내 서버 포켓몬만 선택할 수 있어요. 선택 정보만 공유되며 성장 데이터는 바뀌지 않습니다.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16).frame(width: 472, height: 280, alignment: .topLeading)
        .disabled(controller.busy)
    }
}
