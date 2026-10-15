import Foundation

struct DeviceAuthorization: Decodable, Sendable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code", verificationURI = "verification_uri"
        case expiresIn = "expires_in", interval
    }

    var isValid: Bool {
        !deviceCode.isEmpty && userCode.range(of: "^[A-Z0-9]{4}-[A-Z0-9]{4}$", options: .regularExpression) != nil
            && verificationURI.absoluteString == "https://github.com/login/device"
            && (1...1800).contains(expiresIn) && (1...60).contains(interval)
    }
}

struct GitHubCredential: Codable, Sendable, Equatable {
    let clientID: String
    let userID: Int64
    let accessToken: String
    let expiresAt: Date?
}

enum AuthorizationPoll: Sendable, Equatable {
    case pending
    case slowDown
    case authorized(token: String, expiresIn: Int?)
}

enum ProfileAccessError: Error, Equatable {
    case notConfigured, invalidResponse, denied, expired, invalidCredential, rateLimited, unavailable, storage
}
