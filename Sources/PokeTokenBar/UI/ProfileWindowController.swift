import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class ProfileWindowController {
    let session: ProfileSession
    private var window: NSWindow?

    init(session: ProfileSession? = nil) {
        if let session { self.session = session; return }
        self.session = ProfileSessionFactory.live(directory: AppStatePaths.directory())
    }

    func open(language: AppLanguage) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.title = L(language).profileTitle
        window?.contentView = NSHostingView(rootView: ProfileAccountView(session: session, language: language))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
