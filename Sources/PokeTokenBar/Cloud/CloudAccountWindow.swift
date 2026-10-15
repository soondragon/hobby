import AppKit
import SwiftUI

@MainActor
final class CloudAccountWindow {
    let window: NSWindow
    private let encounter: EncounterPanel?

    init(store: CompanionStore, controller: CloudCompanionController) {
        encounter = (try? CloudConfiguration.load()).map { EncounterPanel(account: controller, serviceURL: $0.serviceURL) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hobby Trainer Cloud"
        let encounter = self.encounter
        let host = NSHostingView(rootView: CloudAccountView(controller: controller, openEncounter: { encounter?.open() }).environment(store))
        // Dynamic intrinsic sizing can recurse during AppKit's display cycle on macOS 26.
        host.sizingOptions = []
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
    }

    func open() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
