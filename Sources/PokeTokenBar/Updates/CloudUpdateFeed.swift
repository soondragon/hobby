import Foundation
import CryptoKit

struct CloudUpdateRelease: Codable, Equatable, Sendable {
    let version: String
    let bundleID: String
    let downloadURL: String
    let sha256: String
    let size: Int
    let minimumOS: Int
    let architecture: String
}

struct CloudUpdateTrust: Codable, Sendable {
    let feedURL: URL
    let publicKey: String

    static func load() throws -> Self {
        guard let file = Bundle.main.url(forResource: "TrainerUpdates", withExtension: "json") else { throw CloudError.configuration }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
}

struct CloudUpdateEnvelope: Codable, Sendable { let payload: String; let signature: String }

enum CloudUpdateFeed {
    static let bundleID = "io.github.soondragon.hobby.cloud"
    static let feedURL = URL(string: "https://hobby-trainer.vercel.app/api/app-release")!

    static func verify(_ data: Data, publicKey: String) throws -> CloudUpdateRelease {
        guard data.count <= 65536,
              let envelope = try? JSONDecoder().decode(CloudUpdateEnvelope.self, from: data),
              let payload = Data(base64Encoded: envelope.payload), let signature = Data(base64Encoded: envelope.signature),
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signature, for: payload) else { throw CloudError.invalidResponse }
        let release = try JSONDecoder().decode(CloudUpdateRelease.self, from: payload)
        guard release.bundleID == bundleID, AppUpdateChannel.cloud.accepts(release.downloadURL),
              UpdateChecker.normalizedReleaseVersion(release.version) == release.version,
              release.sha256.count == 64, release.sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }),
              (1...64_000_000).contains(release.size), release.minimumOS >= 14,
              release.minimumOS <= ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
              release.architecture == "arm64" else { throw CloudError.invalidResponse }
        return release
    }

    static func latest() async -> UpdateChecker.LatestRelease? {
        guard let trust = try? CloudUpdateTrust.load(), trust.feedURL == feedURL else { return nil }
        let session = URLSession(configuration: .ephemeral, delegate: CloudUpdateDownload(limit: 65536), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let (file, response) = try? await session.download(from: trust.feedURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let data = try? Data(contentsOf: file), let release = try? verify(data, publicKey: trust.publicKey) else { return nil }
        return .init(tag: release.version, url: release.downloadURL, package: release)
    }
}

/// No redirects, cookies or auth headers; cancel downloads exceeding the signed size.
final class CloudUpdateDownload: NSObject, URLSessionDownloadDelegate, Sendable {
    let limit: Int64
    init(limit: Int) { self.limit = Int64(limit) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
