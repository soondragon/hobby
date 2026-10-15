#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum CloudPreviewBootstrap {
    static func windowIfRequested() -> NSWindow? {
        guard Bundle.main.object(forInfoDictionaryKey: "CloudPreviewOnly") as? Bool == true else { return nil }
        NSApp.setActivationPolicy(.regular)
        let store = CompanionStore(cloudMode: true)
        let controller = CloudCompanionController(store: store, configuration: try? CloudConfiguration.load())
        store.cloudController = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hobby Trainer Cloud"
        let host = NSHostingView(rootView: CloudAccountView(controller: controller).environment(store))
        host.sizingOptions = []
        window.contentView = host
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
#endif
