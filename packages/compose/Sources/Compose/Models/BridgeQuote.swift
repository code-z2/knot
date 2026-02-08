import Foundation

/// A quote from a bridge provider (e.g. Across).
public struct BridgeQuote: Sendable {
  /// Amount of input token (human-readable).
  public let inputAmount: Decimal
  /// Amount of output token after relay fee (human-readable).
  public let outputAmount: Decimal
  /// Relay fee deducted by the bridge.
  public let relayFee: Decimal
  /// Input token contract address on source chain.
  public let inputToken: String
  /// Output token contract address on destination chain.
  public let outputToken: String
  /// Input amount in wei (string for arbitrary precision).
  public let inputAmountWei: String
  /// Output amount in wei.
  public let outputAmountWei: String
  /// Unix timestamp for fill deadline.
  public let fillDeadline: UInt64
  /// Unix timestamp for exclusivity deadline.
  public let exclusivityDeadline: UInt64
  /// Quote timestamp from the bridge provider.
  public let quoteTimestamp: UInt64
  /// Encoded message payload (empty for simple bridge, Accumulator payload for scatter-gather).
  public let message: Data

  public init(
    inputAmount: Decimal,
    outputAmount: Decimal,
    relayFee: Decimal,
    inputToken: String,
    outputToken: String,
    inputAmountWei: String,
    outputAmountWei: String,
    fillDeadline: UInt64,
    exclusivityDeadline: UInt64,
    quoteTimestamp: UInt64,
    message: Data
  ) {
    self.inputAmount = inputAmount
    self.outputAmount = outputAmount
    self.relayFee = relayFee
    self.inputToken = inputToken
    self.outputToken = outputToken
    self.inputAmountWei = inputAmountWei
    self.outputAmountWei = outputAmountWei
    self.fillDeadline = fillDeadline
    self.exclusivityDeadline = exclusivityDeadline
    self.quoteTimestamp = quoteTimestamp
    self.message = message
  }
}
