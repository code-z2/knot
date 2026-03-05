// SingletonConfigStore.swift
// Created by Peter Anyaogu on 03/03/2026.

import Foundation
import Keychain
import RPC

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

    func save(_ config: StoredSingletonConfig, for eoaAddress: String, mode: ChainSupportMode) throws {
        let data = try JSONEncoder().encode(config)
        try keychain.save(data, account: accountKey(for: eoaAddress, mode: mode), service: service)
    }

    func read(for eoaAddress: String, mode: ChainSupportMode) -> StoredSingletonConfig? {
        guard
            let data = try? keychain.read(
                account: accountKey(for: eoaAddress, mode: mode), service: service,
            )
        else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSingletonConfig.self, from: data)
    }

    private func accountKey(for eoaAddress: String, mode: ChainSupportMode) -> String {
        "singleton.config.v2.\(mode.rawValue.lowercased())."
            + eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
