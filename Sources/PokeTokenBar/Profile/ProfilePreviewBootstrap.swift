#if DEBUG
import AppKit

/// Debug-only account window. Does not construct usage readers or touch Pokémon saves.
@MainActor
enum ProfilePreviewBootstrap {
    static func controllerIfRequested() -> ProfileWindowController? {
        guard Bundle.main.object(forInfoDictionaryKey: "ProfilePreviewOnly") as? Bool == true,
              let path = Bundle.main.object(forInfoDictionaryKey: "ProfilePreviewDirectory") as? String else { return nil }
        NSApp.setActivationPolicy(.regular)
        return ProfileWindowController(session: ProfileSessionFactory.live(directory: URL(fileURLWithPath: path)))
    }
}
#endif
