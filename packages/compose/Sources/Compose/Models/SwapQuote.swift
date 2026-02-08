import Foundation

/// A quote from a swap provider (e.g. LiFi).
public struct SwapQuote: Sendable {
  /// Amount of input token (human-readable).
  public let inputAmount: Decimal
  /// Amount of output token (human-readable).
  public let outputAmount: Decimal
  /// Input token contract address.
  public let inputToken: String
  /// Output token contract address.
  public let outputToken: String
  /// Chain where the swap executes.
  public let chainId: UInt64
  /// Address that needs ERC20 approval (from LiFi estimate.approvalAddress).
  public let approvalTarget: String
  /// Address to call for the swap execution.
  public let swapTarget: String
  /// Ready-to-use swap calldata from the provider.
  public let swapCalldata: Data
  /// Wei value to send with the swap call (non-zero for native input).
  public let swapValue: String
  /// Input amount in wei.
  public let inputAmountWei: String
  /// Output amount in wei.
  public let outputAmountWei: String

  public init(
    inputAmount: Decimal,
    outputAmount: Decimal,
    inputToken: String,
    outputToken: String,
    chainId: UInt64,
    approvalTarget: String,
    swapTarget: String,
    swapCalldata: Data,
    swapValue: String,
    inputAmountWei: String,
    outputAmountWei: String
  ) {
    self.inputAmount = inputAmount
    self.outputAmount = outputAmount
    self.inputToken = inputToken
    self.outputToken = outputToken
    self.chainId = chainId
    self.approvalTarget = approvalTarget
    self.swapTarget = swapTarget
    self.swapCalldata = swapCalldata
    self.swapValue = swapValue
    self.inputAmountWei = inputAmountWei
    self.outputAmountWei = outputAmountWei
  }
}
