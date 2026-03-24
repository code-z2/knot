import Foundation
import RPC

protocol GasUsageProviding: Sendable {
    func fetchUsageSummary(
        eoaAddress: String,
        mode: ChainSupportMode,
    ) async throws -> GasUsageSummary
}

struct GasUsageSummary: Sendable, Equatable {
    let totalUsageNative: String?
    let chainUsage: [GasChainUsage]

    static let empty = GasUsageSummary(totalUsageNative: nil, chainUsage: [])
}

struct GasChainUsage: Sendable, Equatable, Identifiable {
    var id: UInt64 { chainID }
    let chainID: UInt64
    let usageNative: String
}

final class GasUsageService: GasUsageProviding, @unchecked Sendable {
    func fetchUsageSummary(
        eoaAddress: String,
        mode: ChainSupportMode,
    ) async throws -> GasUsageSummary {
        // TODO: Implement relay server usage endpoint
        .empty
    }
}
