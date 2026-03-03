import Foundation
import Keychain

struct SingletonConfigStore {
    private let keychain: KeychainStoreProviding
    private let service: String

    init(
        keychain: KeychainStoreProviding = KeychainStoreService(),
        service: String = "fi.knot.singleton.config",
    ) {
        self.keychain = keychain
        self.service = service
    }

    func save(_ config: StoredSingletonConfig, for eoaAddress: String) throws {
        let data = try JSONEncoder().encode(config)
        try keychain.save(data, account: accountKey(for: eoaAddress), service: service)
    }

    func read(for eoaAddress: String) -> StoredSingletonConfig? {
        guard let data = try? keychain.read(account: accountKey(for: eoaAddress), service: service)
        else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSingletonConfig.self, from: data)
    }

    private func accountKey(for eoaAddress: String) -> String {
        "singleton.config.v1." + eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct StoredSingletonConfig: Codable, Sendable, Equatable {
    let delegateAddress: String
    let accumulatorFactory: String
    let version: String

    init(delegateAddress: String, accumulatorFactory: String, version: String) {
        self.delegateAddress = delegateAddress.lowercased()
        self.accumulatorFactory = accumulatorFactory.lowercased()
        self.version = version
    }
}
