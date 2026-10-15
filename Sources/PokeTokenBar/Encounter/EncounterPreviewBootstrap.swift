#if DEBUG
import AppKit
import SwiftUI
import Observation

@MainActor
enum EncounterPreviewBootstrap {
    private static var controls: NSWindow?
    static func windowIfRequested() -> NSWindow? {
        guard Bundle.main.object(forInfoDictionaryKey: "EncounterPreviewOnly") as? Bool == true else { return nil }
        NSApp.setActivationPolicy(.regular)
        let model = EncounterPreviewModel()
        let window = EncounterWindowStyle.floatingPanel()
        window.title = "Floating Encounter Preview"
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.title = "플로팅 펫 · 로컬 샘플"
        let settingsHost = NSHostingView(rootView: VStack(spacing: 12) {
            Text("로컬 UI 샘플 · 실제 계정 데이터 아님").font(.caption)
            Button("반대 시점") { model.reversed.toggle() }
        }.frame(width: 300, height: 100))
        settingsHost.sizingOptions = []
        settings.contentView = settingsHost
        settings.isReleasedWhenClosed = false
        controls = settings
        let host = NSHostingView(rootView: EncounterPreview(model: model,
            settings: { settings.makeKeyAndOrderFront(nil) }, hide: { [weak window] in window?.orderOut(nil) }))
        host.sizingOptions = []
        window.contentView = host
        window.center(); window.makeKeyAndOrderFront(nil)
        settings.setFrameOrigin(NSPoint(x: window.frame.maxX + 20, y: window.frame.minY))
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}

@MainActor @Observable
private final class EncounterPreviewModel {
    var reversed = false
    var members: [EncounterMember] { [
        .init(isSelf: !reversed, alias: "trainer-one", pokemon: .init(speciesID: 6, level: 36, isShiny: false, unownForm: nil)),
        .init(isSelf: reversed, alias: "trainer-two", pokemon: .init(speciesID: 9, level: 36, isShiny: false, unownForm: nil))
    ] }
}

private struct EncounterPreview: View {
    let model: EncounterPreviewModel
    let settings: () -> Void
    let hide: () -> Void
    var body: some View { EncounterDesktopView(members: model.members, settings: settings, hide: hide) }
}
#endif
