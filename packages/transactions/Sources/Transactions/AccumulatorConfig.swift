import Foundation

/// Configuration for resolving the user's Accumulator address.
/// With counterfactual deterministic deployment, the factory lives at
/// the same address on every chain.
public struct AccumulatorConfig: Sendable {
  /// AccumulatorFactory contract address (same on all chains via CREATE2).
  public let factoryAddress: String
  /// Across SpokePool / messenger address per chain ID.
  public let messengerByChain: [UInt64: String]

  public init(factoryAddress: String, messengerByChain: [UInt64: String]) {
    self.factoryAddress = factoryAddress
    self.messengerByChain = messengerByChain
  }

  /// Default config — placeholder addresses until contracts are deployed.
  /// Replace with actual deployed addresses once deterministic deployment is done.
  public static let `default` = AccumulatorConfig(
    factoryAddress: "",
    messengerByChain: [:]
  )
}
