import XCTest
import CryptoKit
@testable import PokeTokenBar

final class CloudUpdateFeedTests: XCTestCase {
    private func signed(_ key: Curve25519.Signing.PrivateKey, bundleID: String = CloudUpdateFeed.bundleID,
                        url: String = "https://hobby-trainer.vercel.app/downloads/cloud/trainer-0.3.0.zip") throws -> Data {
        let release = CloudUpdateRelease(version: "0.3.0", bundleID: bundleID, downloadURL: url,
                                         sha256: String(repeating: "a", count: 64), size: 12, minimumOS: 14, architecture: "arm64")
        let payload = try JSONEncoder().encode(release)
        return try JSONEncoder().encode(CloudUpdateEnvelope(payload: payload.base64EncodedString(), signature: key.signature(for: payload).base64EncodedString()))
    }

    func testValidPublisherSignatureAndExactChannel() throws {
        let key = Curve25519.Signing.PrivateKey()
        XCTAssertEqual(try CloudUpdateFeed.verify(signed(key), publicKey: key.publicKey.rawRepresentation.base64EncodedString()).version, "0.3.0")
    }

    func testDifferentSignerOrAlteredSignedPayloadIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        XCTAssertThrowsError(try CloudUpdateFeed.verify(signed(key), publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        let original = try JSONDecoder().decode(CloudUpdateEnvelope.self, from: signed(key))
        let changed = CloudUpdateEnvelope(payload: Data("{}".utf8).base64EncodedString(), signature: original.signature)
        XCTAssertThrowsError(try CloudUpdateFeed.verify(JSONEncoder().encode(changed), publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
    }

    func testEvenSignedUpstreamBundleOrForeignArtifactIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey(); let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertThrowsError(try CloudUpdateFeed.verify(signed(key, bundleID: "io.github.chattymin.poketokenbar"), publicKey: publicKey))
        XCTAssertThrowsError(try CloudUpdateFeed.verify(signed(key, url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v9.0.0"), publicKey: publicKey))
    }

    func testInstallScriptWaitsWithoutKillingAndHasRollback() {
        XCTAssertTrue(CloudUpdateInstallation.script.contains("kill -0"))
        XCTAssertFalse(CloudUpdateInstallation.script.contains("kill -9"))
        XCTAssertTrue(CloudUpdateInstallation.script.contains("/bin/mv \"$3\" \"$2\""))
        XCTAssertFalse(CloudUpdateInstallation.script.contains("brew"))
    }
}

extension CloudUpdateFeedTests {
    func testReleaseArtifactUsesRealSignatureHashAndExtractedBundle() throws {
        guard let archive = ProcessInfo.processInfo.environment["PTB_RELEASE_ARCHIVE"],
              let manifest = ProcessInfo.processInfo.environment["PTB_RELEASE_MANIFEST"],
              let trustPath = ProcessInfo.processInfo.environment["PTB_RELEASE_TRUST"] else {
            throw XCTSkip("Release artifact fixture not selected")
        }
        let trust = try JSONDecoder().decode(CloudUpdateTrust.self, from: Data(contentsOf: URL(fileURLWithPath: trustPath)))
        let release = try CloudUpdateFeed.verify(Data(contentsOf: URL(fileURLWithPath: manifest)), publicKey: trust.publicKey)
        let archiveURL = URL(fileURLWithPath: archive)
        let bytes = try Data(contentsOf: archiveURL)
        XCTAssertEqual(bytes.count, release.size)
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), release.sha256)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = try CloudUpdateInstaller.extract(file: archiveURL, release: release, target: root.appendingPathComponent("PokeTokenBar Cloud.app"))
        XCTAssertEqual(Bundle(url: installation.candidate)?.bundleIdentifier, CloudUpdateFeed.bundleID)
        XCTAssertEqual(Bundle(url: installation.candidate)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, release.version)
    }
}
