import Foundation

/// Release ownership is independent of the upstream source version.
enum AppUpdateChannel: Sendable {
    case upstream
    case cloud

    static func installed(bundle: Bundle = .main) -> Self {
        bundle.bundleIdentifier == "io.github.chattymin.poketokenbar" ? .upstream : .cloud
    }

    var repository: String {
        switch self {
        case .upstream: "chattymin/PokeTokenBar"
        case .cloud: "soondragon/hobby"
        }
    }

    var allowsHomebrewUpgrade: Bool { self == .upstream }

    func accepts(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let prefix = "/\(repository)/releases/tag/"
        return url.path.hasPrefix(prefix) && url.path.count > prefix.count
    }
}
