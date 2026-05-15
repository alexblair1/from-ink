import ComposableArchitecture
import Foundation
import Security

/// TCA dependency for Keychain-backed IntegrationAccount storage.
/// Accounts are stored per-provider with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
/// Not synced via iCloud Keychain — each device authenticates independently.
///
struct KeychainService: Sendable {
    var save: @Sendable (IntegrationAccount) throws -> Void
    var accounts: @Sendable (OAuthProvider) throws -> [IntegrationAccount]
    var account: @Sendable (UUID) throws -> IntegrationAccount?
    var allAccounts: @Sendable () throws -> [IntegrationAccount]
    var delete: @Sendable (UUID) throws -> Void
}

// MARK: - DependencyKey

extension KeychainService: DependencyKey {
    static let liveValue: KeychainService = {
        let service = "com.fromink.oauth"
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        return KeychainService(
            save: { account in
                let data = try encoder.encode(account)
                let key = "\(account.provider.rawValue)-\(account.id.uuidString)"

                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                ]

                // Delete existing if present, then add.
                SecItemDelete(query as CFDictionary)

                let addQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                ]
                let status = SecItemAdd(addQuery as CFDictionary, nil)
                guard status == errSecSuccess else {
                    throw OAuthError.keychainError(status)
                }
            },

            accounts: { provider in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnData as String: true,
                    kSecReturnAttributes as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ]

                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                guard status == errSecSuccess,
                      let items = result as? [[String: Any]]
                else {
                    if status == errSecItemNotFound { return [] }
                    throw OAuthError.keychainError(status)
                }

                return items.compactMap { item -> IntegrationAccount? in
                    guard let data = item[kSecValueData as String] as? Data,
                          let account = try? decoder.decode(IntegrationAccount.self, from: data),
                          account.provider == provider
                    else { return nil }
                    return account
                }
            },

            account: { id in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnData as String: true,
                    kSecReturnAttributes as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ]

                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                guard status == errSecSuccess,
                      let items = result as? [[String: Any]]
                else {
                    if status == errSecItemNotFound { return nil }
                    throw OAuthError.keychainError(status)
                }

                return items.compactMap { item -> IntegrationAccount? in
                    guard let data = item[kSecValueData as String] as? Data,
                          let account = try? decoder.decode(IntegrationAccount.self, from: data),
                          account.id == id
                    else { return nil }
                    return account
                }.first
            },

            allAccounts: {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ]

                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                guard status == errSecSuccess,
                      let items = result as? [[String: Any]]
                else {
                    if status == errSecItemNotFound { return [] }
                    throw OAuthError.keychainError(status)
                }

                return items.compactMap { item -> IntegrationAccount? in
                    guard let data = item[kSecValueData as String] as? Data,
                          let account = try? decoder.decode(IntegrationAccount.self, from: data)
                    else { return nil }
                    return account
                }
            },

            delete: { id in
                // Find the account first to build the correct key.
                let allQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnData as String: true,
                    kSecReturnAttributes as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                ]

                var result: CFTypeRef?
                let status = SecItemCopyMatching(allQuery as CFDictionary, &result)

                guard status == errSecSuccess,
                      let items = result as? [[String: Any]]
                else { return }

                for item in items {
                    guard let data = item[kSecValueData as String] as? Data,
                          let account = try? decoder.decode(IntegrationAccount.self, from: data),
                          account.id == id,
                          let key = item[kSecAttrAccount as String] as? String
                    else { continue }

                    let deleteQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecAttrAccount as String: key,
                    ]
                    SecItemDelete(deleteQuery as CFDictionary)
                    return
                }
            }
        )
    }()

    static let testValue: KeychainService = {
        let storage = LockIsolated<[UUID: IntegrationAccount]>([:])
        return KeychainService(
            save: { account in
                storage.withValue { $0[account.id] = account }
            },
            accounts: { provider in
                storage.withValue { $0.values.filter { $0.provider == provider } }
            },
            account: { id in
                storage.withValue { $0[id] }
            },
            allAccounts: {
                storage.withValue { Array($0.values) }
            },
            delete: { id in
                storage.withValue { $0[id] = nil }
            }
        )
    }()
}

// MARK: - DependencyValues

extension DependencyValues {
    var keychainService: KeychainService {
        get { self[KeychainService.self] }
        set { self[KeychainService.self] = newValue }
    }
}
