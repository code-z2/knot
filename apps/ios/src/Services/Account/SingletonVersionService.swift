// SingletonVersionService.swift
// Created by Peter Anyaogu on 03/03/2026.

import Foundation
import RPC

final class SingletonVersionService: Sendable {
    private let rpcClient: RPCClient

    init(rpcClient: RPCClient = RPCClient()) {
        self.rpcClient = rpcClient
    }

    func fetchLatest() async -> StoredSingletonConfig? {
        do {
            let response = try await rpcClient.relaySingletonVersion()
            guard response.ok else { return nil }
            return StoredSingletonConfig(
                delegateAddress: response.currentSingleton,
                accumulatorFactory: response.accumulatorFactory,
                version: response.version,
            )
        } catch {
            print(
                "⚠️ [SingletonVersionService] Failed to fetch singleton version: \(error.localizedDescription)",
            )
            return nil
        }
    }
}
