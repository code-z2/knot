import Foundation
import Security

public enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
    case dataNotFound
    case invalidData
}

extension KeychainStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain operation failed (\(status)): \(message)"
            }
            return "Keychain operation failed with status \(status)."
        case .dataNotFound:
            return "No keychain item was found for the requested account/service."
        case .invalidData:
            return "Keychain returned data in an unexpected format."
        }
    }
}

public protocol KeychainStoring {
    func save(_ data: Data, account: String, service: String) throws
    func read(account: String, service: String) throws -> Data
    func delete(account: String, service: String) throws
}

public struct KeychainStore: KeychainStoring {
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
