import Foundation

/// Protocol for same-chain swap providers.
///
/// Implementations fetch quotes from external APIs and return ready-to-use
/// swap calldata. The RouteComposer handles ERC20 approval calls separately —
/// providers only return the swap quote with the approval target address.
public protocol SwapProvider: Sendable {
    /// Fetch a swap quote.
    ///
    /// - Parameters:
    ///   - inputToken: Token contract address to swap from.
    ///   - outputToken: Token contract address to swap to.
    ///   - inputAmountWei: Amount in wei.
    ///   - chainId: Chain where the swap executes.
    ///   - fromAddress: Address initiating the swap (smart account).
    func getQuote(
        inputToken: String,
        outputToken: String,
        inputAmountWei: String,
        chainId: UInt64,
        fromAddress: String,
    ) async throws -> SwapQuoteModel
}
