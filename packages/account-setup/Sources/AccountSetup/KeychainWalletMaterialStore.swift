import Foundation
import Keychain
import Security
import SignHandler

public struct KeychainWalletMaterialStore: WalletMaterialStoring {
    private struct StoredWalletSeedRecord: Codable, Equatable, Sendable {
        let version: Int
        let eoaAddress: String
        let mnemonic: String
        let createdAt: Date
    }

    private enum Constants {
        static let schemaVersion = 1
        static let accountPrefix = "wallet.seed.v1."
    }

    private let service: String
    private let walletFactory: WalletMaterialFactory

    public init(
        service: String = "fi.knot.wallet.seed",
        walletFactory: WalletMaterialFactory = .init(),
    ) {
        self.service = service
        self.walletFactory = walletFactory
    }

    public func save(_ wallet: WalletMaterialModel, for eoaAddress: String) throws {
        let normalizedAddress = normalizedAddressKey(eoaAddress)
        guard !normalizedAddress.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard !wallet.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }

        let record = StoredWalletSeedRecord(
            version: Constants.schemaVersion,
            eoaAddress: normalizedAddress,
            mnemonic: wallet.mnemonic,
            createdAt: Date(),
        )
        let data = try JSONEncoder().encode(record)
        let account = keychainAccount(for: normalizedAddress)
        let synchronizable = strictSynchronizableValue()

        var deleteQuery = baseQuery(account: account)
        deleteQuery[kSecAttrSynchronizable as String] = synchronizable
        SecItemDelete(deleteQuery as CFDictionary)

        var saveQuery = baseQuery(account: account)
        saveQuery[kSecValueData as String] = data
        saveQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        saveQuery[kSecAttrSynchronizable as String] = synchronizable

        let status = SecItemAdd(saveQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
    }

    public func read(for eoaAddress: String) throws -> WalletMaterialModel {
        let normalizedAddress = normalizedAddressKey(eoaAddress)
        let account = keychainAccount(for: normalizedAddress)

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = strictSynchronizableValue()

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw CocoaError(.fileReadNoSuchFile) }
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainStoreError.invalidData }

        let record = try JSONDecoder().decode(StoredWalletSeedRecord.self, from: data)
        let privateKeyHex = try walletFactory.mnemonicToPrivateKey(record.mnemonic)
        return WalletMaterialModel(
            mnemonic: record.mnemonic,
            privateKeyHex: privateKeyHex,
            eoaAddress: normalizedAddressKey(record.eoaAddress),
        )
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainAccount(for normalizedAddress: String) -> String {
        Constants.accountPrefix + normalizedAddress
    }

    private func normalizedAddressKey(_ eoaAddress: String) -> String {
        eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func strictSynchronizableValue() -> CFBoolean {
        #if targetEnvironment(simulator)
            return kCFBooleanFalse
        #else
            return kCFBooleanTrue
        #endif
    }
}
