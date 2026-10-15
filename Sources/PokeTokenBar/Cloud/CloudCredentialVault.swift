import Foundation
import Security

struct CloudCredential: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

@MainActor
struct CloudCredentialVault {
    let project: String
    private var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.soondragon.hobby.cloud",
        kSecAttrAccount as String: project,
        kSecAttrSynchronizable as String: false
    ] }

    func read() throws -> CloudCredential? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = KeychainReader.copyMatching(query, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CloudError.storage }
        return try JSONDecoder().decode(CloudCredential.self, from: data)
    }

    func write(_ value: CloudCredential) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw CloudError.storage }
        } else if status != errSecSuccess { throw CloudError.storage }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudError.storage }
    }
}
