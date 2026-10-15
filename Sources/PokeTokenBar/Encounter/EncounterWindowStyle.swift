import AppKit
import SwiftUI

@MainActor
enum EncounterWindowStyle {
    static func floatingPanel(size: NSSize = NSSize(width: 450, height: 402)) -> NSPanel {
        let panel = DesktopEncounterWindow(contentRect: NSRect(origin: .zero, size: size),
                                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

private final class DesktopEncounterWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct EncounterDesktopView: View {
    let members: [EncounterMember]
    let settings: () -> Void
    let hide: () -> Void
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Button(action: settings) { Image(systemName: "slider.horizontal.3") }
                    .help("초대·포켓몬 선택")
                Button(action: hide) { Image(systemName: "xmark") }.help("플로팅 펫 숨기기")
            }
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
            .padding(8).background(.regularMaterial, in: Capsule())
            .fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
            EncounterBattleView(members: members)
        }
        .frame(width: 450, height: 402)
        .background(Color.clear)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("초대·포켓몬 선택", action: settings)
            Button("플로팅 펫 숨기기", action: hide)
        }
    }
}
