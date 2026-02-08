import Foundation
import Transactions

/// Protocol for cross-chain bridge providers.
///
/// Implementations fetch quotes from external APIs and encode deposit calldata
/// for on-chain execution. The RouteComposer handles ERC20 approval calls
/// separately — providers only return the deposit call itself.
public protocol BridgeProvider: Sendable {
  /// Fetch a bridge quote.
  ///
  /// - Parameters:
  ///   - inputToken: Token contract address on the source chain.
  ///   - outputToken: Token contract address on the destination chain.
  ///   - inputAmountWei: Amount in wei (source token decimals).
  ///   - sourceChainId: Source chain ID.
  ///   - destinationChainId: Destination chain ID.
  ///   - recipient: Address that receives tokens on the destination chain
  ///     (user for simple bridge, accumulator for scatter-gather).
  ///   - message: Encoded message payload (empty for simple bridge,
  ///     Accumulator message for scatter-gather).
  func getQuote(
    inputToken: String,
    outputToken: String,
    inputAmountWei: String,
    sourceChainId: UInt64,
    destinationChainId: UInt64,
    recipient: String,
    message: Data
  ) async throws -> BridgeQuote

  /// Encode the deposit call from a quote.
  ///
  /// Returns a `Call` targeting the bridge contract on the source chain.
  /// The caller must prepend an ERC20 approve call if the input is not native.
  func encodeDeposit(
    quote: BridgeQuote,
    depositor: String,
    recipient: String,
    sourceChainId: UInt64,
    destinationChainId: UInt64
  ) throws -> Call

  /// Whether this provider can bridge the given token between two chains.
  func canBridge(token: String, sourceChain: UInt64, destChain: UInt64) -> Bool
}
