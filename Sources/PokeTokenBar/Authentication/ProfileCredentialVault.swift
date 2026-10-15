import Foundation
import Security

@MainActor
protocol ProfileCredentialStoring {
    func read() throws -> GitHubCredential?
    func write(_ credential: GitHubCredential) throws
    func clear() throws
}

/// Reads are explicit user actions. Opening the app or popover never queries the Keychain.
@MainActor
struct ProfileCredentialVault: ProfileCredentialStoring {
    let clientID: String
    private var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.soondragon.hobby.profile",
        kSecAttrAccount as String: clientID,
        kSecAttrSynchronizable as String: false
    ] }

    func read() throws -> GitHubCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = KeychainReader.copyMatching(request, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ProfileAccessError.storage }
        let credential = try JSONDecoder().decode(GitHubCredential.self, from: data)
        guard credential.clientID == clientID else { throw ProfileAccessError.invalidCredential }
        return credential
    }

    func write(_ credential: GitHubCredential) throws {
        guard credential.clientID == clientID else { throw ProfileAccessError.invalidCredential }
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw ProfileAccessError.storage }
        } else if status != errSecSuccess { throw ProfileAccessError.storage }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProfileAccessError.storage }
    }
}
