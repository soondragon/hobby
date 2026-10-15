import AppKit
import SwiftUI

@MainActor
final class CloudAccountWindow {
    let window: NSWindow

    init(store: CompanionStore, controller: CloudCompanionController) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hobby Trainer Cloud"
        let host = NSHostingView(rootView: CloudAccountView(controller: controller).environment(store))
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
