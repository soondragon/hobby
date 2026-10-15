#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum EncounterPreviewBootstrap {
    static func windowIfRequested() -> NSWindow? {
        guard Bundle.main.object(forInfoDictionaryKey: "EncounterPreviewOnly") as? Bool == true else { return nil }
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 472, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Floating Encounter Preview"
        let host = NSHostingView(rootView: EncounterPreview())
        host.sizingOptions = []
        window.contentView = host; window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        return window
    }
}

private struct EncounterPreview: View {
    @State private var reversed = false
    var body: some View {
        VStack(spacing: 12) {
            Text("로컬 UI 샘플 · 실제 계정 데이터 아님").font(.caption)
            EncounterBattleView(members: [
                .init(isSelf: !reversed, alias: "trainer-one", pokemon: .init(speciesID: 6, level: 36, isShiny: false, unownForm: nil)),
                .init(isSelf: reversed, alias: "trainer-two", pokemon: .init(speciesID: 9, level: 36, isShiny: false, unownForm: nil))])
            Button("반대 시점") { reversed.toggle() }
        }.padding(16)
    }
}
#endif
