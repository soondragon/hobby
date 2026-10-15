import Foundation

@MainActor
protocol ProfilePersisting {
    func load(clientID: String) throws -> GitHubProfile?
    func save(_ profile: GitHubProfile, clientID: String) throws
    func clear() throws
}

@MainActor
struct ProfileRepository: ProfilePersisting {
    let fileURL: URL
    private struct Record: Codable { let clientID: String; let profile: GitHubProfile }

    func load(clientID: String) throws -> GitHubProfile? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: fileURL))
        return record.clientID == clientID && record.profile.isValid ? record.profile : nil
    }

    func save(_ profile: GitHubProfile, clientID: String) throws {
        guard profile.isValid else { throw ProfileAccessError.invalidResponse }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Record(clientID: clientID, profile: profile)).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}
