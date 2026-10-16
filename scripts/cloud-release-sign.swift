import Foundation
import CryptoKit

let arguments = CommandLine.arguments
let keyURL = URL(fileURLWithPath: arguments[1])
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: keyURL.path) {
    key = try .init(rawRepresentation: Data(contentsOf: keyURL))
} else {
    guard arguments[2] == "trust" else { fatalError("Release signing key missing; do not rotate it implicitly") }
    key = .init()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(atPath: keyURL.path, contents: key.rawRepresentation, attributes: [.posixPermissions: 0o600]) else { fatalError("Cannot create release signing key") }
}
if arguments[2] == "trust" {
    let trust = ["feedURL": "https://hobby-trainer.vercel.app/api/app-release", "publicKey": key.publicKey.rawRepresentation.base64EncodedString()]
    try JSONSerialization.data(withJSONObject: trust, options: [.sortedKeys]).write(to: URL(fileURLWithPath: arguments[3]))
} else {
    let payload = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    let envelope = ["payload": payload.base64EncodedString(), "signature": try key.signature(for: payload).base64EncodedString()]
    try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: URL(fileURLWithPath: arguments[3]))
}
