import Foundation

@MainActor
protocol CloudAuthenticating: AnyObject {
    var userID: UUID? { get }
    func signIn() async throws
    func restore() async throws
    func accessToken() async throws -> String
    func signOut() throws
}

protocol CloudSaveServing: Sendable {
    func read(token: String) async throws -> CloudSaveEnvelope
    func write(_ command: CloudSaveCommand, token: String) async throws -> CloudSaveReceipt
}

struct CloudSaveRepository: CloudSaveServing {
    let configuration: CloudConfiguration
    private let transport = CloudTransport()
    func read(token: String) async throws -> CloudSaveEnvelope {
        try await transport.request(CloudSaveEnvelope.self,
            url: configuration.serviceURL.appendingPathComponent("api/companion"), token: token)
    }
    func write(_ command: CloudSaveCommand, token: String) async throws -> CloudSaveReceipt {
        try await transport.request(CloudSaveReceipt.self,
            url: configuration.serviceURL.appendingPathComponent("api/companion"), method: "PUT", token: token,
            body: JSONEncoder().encode(command))
    }
}
