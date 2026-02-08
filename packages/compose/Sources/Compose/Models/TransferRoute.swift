import Foundation
import Transactions

/// A resolved transfer route with ready-to-sign calldata.
public struct TransferRoute: Sendable {
  /// Human-readable steps for UI visualization.
  public let steps: [RouteStep]
  /// Ready-to-sign chain calls for AAExecutionService.
  public let chainCalls: [ChainCalls]
  /// Non-nil for multi-chain (accumulate) routes; passed to executeChainCalls.
  public let jobId: Data?
  /// The destination chain where funds ultimately arrive.
  public let destinationChainId: UInt64
  /// Estimated amount the recipient receives.
  public let estimatedAmountOut: Decimal
  /// Symbol of the output token.
  public let estimatedAmountOutSymbol: String

  public init(
    steps: [RouteStep],
    chainCalls: [ChainCalls],
    jobId: Data?,
    destinationChainId: UInt64,
    estimatedAmountOut: Decimal,
    estimatedAmountOutSymbol: String
  ) {
    self.steps = steps
    self.chainCalls = chainCalls
    self.jobId = jobId
    self.destinationChainId = destinationChainId
    self.estimatedAmountOut = estimatedAmountOut
    self.estimatedAmountOutSymbol = estimatedAmountOutSymbol
  }
}

/// A single step in a transfer route, for UI display.
public struct RouteStep: Sendable, Identifiable {
  public let id: UUID
  public let chainId: UInt64
  public let chainName: String
  public let action: RouteAction
  public let inputAmount: Decimal
  public let inputSymbol: String
  public let outputAmount: Decimal
  public let outputSymbol: String

  public init(
    id: UUID = UUID(),
    chainId: UInt64,
    chainName: String,
    action: RouteAction,
    inputAmount: Decimal,
    inputSymbol: String,
    outputAmount: Decimal,
    outputSymbol: String
  ) {
    self.id = id
    self.chainId = chainId
    self.chainName = chainName
    self.action = action
    self.inputAmount = inputAmount
    self.inputSymbol = inputSymbol
    self.outputAmount = outputAmount
    self.outputSymbol = outputSymbol
  }
}

/// The type of action a route step performs.
public enum RouteAction: Sendable {
  /// Direct ERC20 transfer or native ETH send.
  case transfer
  /// On-chain swap via LiFi.
  case swap
  /// Cross-chain bridge via Across.
  case bridge
  /// Cross-chain bridge into Accumulator (scatter-gather).
  case accumulate
}

/// Errors from route resolution.
public enum RouteError: Error, Sendable {
  case noRouteFound(reason: String)
  case quoteUnavailable(provider: String, reason: String)
  case insufficientBalance
  case unsupportedChain(UInt64)
  case unsupportedAsset(String)
}
