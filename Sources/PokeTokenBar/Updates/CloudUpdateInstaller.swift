import Foundation
import CryptoKit

struct CloudUpdateInstallation: Sendable {
    let candidate: URL
    let target: URL
    let workspace: URL

    func launch(after pid: Int32) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.script, "sh", candidate.path, target.path, workspace.appendingPathComponent("previous.app").path, String(pid)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    // Never force-kill a process with pending saves. Keep the previous bundle for recovery.
    static let script = """
    for i in $(seq 1 120); do kill -0 "$4" 2>/dev/null || break; sleep 0.5; done
    kill -0 "$4" 2>/dev/null && exit 1
    /bin/mv "$2" "$3" || exit 1
    if /bin/mv "$1" "$2" && /usr/bin/codesign --verify --strict "$2"; then
      /usr/bin/open "$2"
    else
      [ -e "$2" ] && /bin/mv "$2" "$1"
      /bin/mv "$3" "$2"
      /usr/bin/open "$2"
    fi
    """
}

enum CloudUpdateInstaller {
    static func prepare(_ release: CloudUpdateRelease, target: URL = Bundle.main.bundleURL) async throws -> CloudUpdateInstallation {
        guard Bundle(url: target)?.bundleIdentifier == CloudUpdateFeed.bundleID,
              target.pathExtension == "app", AppUpdateChannel.cloud.accepts(release.downloadURL),
              let url = URL(string: release.downloadURL) else { throw CloudError.configuration }
        let session = URLSession(configuration: .ephemeral, delegate: CloudUpdateDownload(limit: release.size), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CloudError.transport }
        let archive = try Data(contentsOf: file, options: .mappedIfSafe)
        guard archive.count == release.size, SHA256.hash(data: archive).map({ String(format: "%02x", $0) }).joined() == release.sha256 else {
            throw CloudError.invalidResponse
        }
        return try await Task.detached { try extract(file: file, release: release, target: target) }.value
    }

    static func extract(file: URL, release: CloudUpdateRelease, target: URL) throws -> CloudUpdateInstallation {
        let files = try run("/usr/bin/unzip", ["-Z", "-1", file.path]).split(separator: "\n").map(String.init)
        guard !files.isEmpty, files.count <= 5000,
              files.allSatisfy({ $0.hasPrefix("PokeTokenBar Cloud.app/") && !$0.split(separator: "/").contains("..") && !$0.contains("\\") }) else { throw CloudError.invalidResponse }
        let listing = try run("/usr/bin/unzip", ["-Z", "-l", file.path])
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else { throw CloudError.invalidResponse }
        let workspace = target.deletingLastPathComponent().appendingPathComponent(".trainer-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            _ = try run("/usr/bin/ditto", ["-x", "-k", file.path, workspace.path])
            let candidate = workspace.appendingPathComponent("PokeTokenBar Cloud.app")
            guard let bundle = Bundle(url: candidate), bundle.bundleIdentifier == CloudUpdateFeed.bundleID,
                  bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version,
                  bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "PokeTokenBar" else { throw CloudError.invalidResponse }
            _ = try run("/usr/bin/codesign", ["--verify", "--strict", candidate.path])
            return .init(candidate: candidate, target: target, workspace: workspace)
        } catch {
            try? FileManager.default.removeItem(at: workspace)
            throw error
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CloudError.invalidResponse }
        return String(decoding: data, as: UTF8.self)
    }
}
