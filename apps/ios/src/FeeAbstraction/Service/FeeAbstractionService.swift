import Foundation
import RPC

@MainActor
final class FeeAbstractionService {
    private let rpcClient: RPCClient

    init(rpcClient: RPCClient = RPCClient()) {
        self.rpcClient = rpcClient
    }

    func refreshCredit(
        eoaAddress: String,
        mode: ChainSupportMode,
        store: FeeAbstractionStore,
    ) async throws {
        let credit = try await rpcClient.relayCredit(
            account: eoaAddress,
            supportMode: mode,
        )

        store.updateCredit(
            balanceNative: credit.balanceNative,
            initialized: credit.initialized,
        )
    }
}
