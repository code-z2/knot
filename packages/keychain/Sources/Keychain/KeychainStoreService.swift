import Foundation
import Security

public protocol KeychainStoreProviding {
    func save(_ data: Data, account: String, service: String) throws
    func read(account: String, service: String) throws -> Data
    func delete(account: String, service: String) throws
}

public struct KeychainStoreService: KeychainStoreProviding {
    public init() {}

    public func save(_ data: Data, account: String, service: String) throws {
        let query = baseQuery(account: account, service: service)
        SecItemDelete(query as CFDictionary)

        var saveQuery = query
        saveQuery[kSecValueData as String] = data

        let status = SecItemAdd(saveQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
    }

    public func read(account: String, service: String) throws -> Data {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { throw KeychainStoreError.dataNotFound }
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainStoreError.invalidData }
        return data
    }

    public func delete(account: String, service: String) throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}
