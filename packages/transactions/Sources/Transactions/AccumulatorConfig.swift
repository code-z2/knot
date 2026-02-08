import Foundation

/// Configuration for resolving the user's Accumulator address.
/// With counterfactual deterministic deployment, the factory lives at
/// the same address on every chain.
public struct AccumulatorConfig: Sendable {
  /// AccumulatorFactory contract address (same on all chains).
  public let factoryAddress: String
  /// Across SpokePool / messenger address.
  public let messengerAddress: String

  public init(factoryAddress: String, messengerAddress: String) {
    self.factoryAddress = factoryAddress
    self.messengerAddress = messengerAddress
  }

  /// Default config — placeholder addresses until contracts are deployed.
  /// Replace with actual deployed addresses once deterministic deployment is done.
  public static let `default` = AccumulatorConfig(
    factoryAddress: "",
    messengerAddress: ""
  )
}
