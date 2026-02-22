import Foundation
import RPC

/// Best-effort faucet that requests testnet USDC and ETH for a newly created account.
/// All errors are silently swallowed — the faucet is purely additive and never blocks the user.
final class FaucetService: Sendable {
    private let rpcClient: RPCClient

    init(
        rpcClient: RPCClient = RPCClient(),
    ) {
        self.rpcClient = rpcClient
    }

    /// Fire-and-forget: requests the server to fund the given EOA on all testnet chains.
    /// Returns silently on any failure.
    func fundAccount(eoaAddress: String, mode: ChainSupportMode) async {
        do {
            _ = try await rpcClient.relayFaucetFund(
                eoaAddress: eoaAddress,
                supportMode: mode,
            )
        } catch {
            // Silently fail — faucet funding is best-effort.
        }
    }
}
