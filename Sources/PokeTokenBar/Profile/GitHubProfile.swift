import Foundation

struct GitHubProfile: Codable, Sendable, Equatable {
    let id: Int64
    let login: String
    let name: String?

    var alias: String { "@" + login }
    var isValid: Bool {
        id > 0 && login.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", options: .regularExpression) != nil
    }
}
