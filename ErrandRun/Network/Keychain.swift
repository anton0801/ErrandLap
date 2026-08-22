//
//  Keychain.swift
//  ErrandRun
//
//  Tokens live in the Keychain, not in UserDefaults: they stay encrypted at rest,
//  never leave this device, and are gone when the app is removed.
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Secure storage returned an unexpected result (\(status))."
        }
    }
}

/// A single item holds the whole session. One read, one write, no scattered secrets.
struct StoredSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: Date
    var refreshExpiresAt: Date
    var sessionID: String
    var userID: String
    var email: String
    var displayName: String

    var accessIsFresh: Bool {
        // Treat a token about to expire as already expired: one refresh beats one failure.
        accessExpiresAt.timeIntervalSinceNow > 60
    }

    var refreshIsUsable: Bool {
        refreshExpiresAt.timeIntervalSinceNow > 0
    }
}

enum Keychain {
    private static let service = "app.errandrun.session"
    private static let account = "current"

    static func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Available after the first unlock, and never synced to iCloud or a backup
            // that could be restored onto another device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
            return
        }

        throw KeychainError.unexpectedStatus(status)
    }

    static func load() -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
