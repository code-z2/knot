import Foundation

public enum AAConstants {
  public static let entryPointV09 = "0x433709009B8330FDa32311DF1C2AFA402eD8D009"

  // Replace these placeholders with deployed addresses per chain.
  public static let messengerByChain: [UInt64: String] = [
    1: "0x0000000000000000000000000000000000000000",
    11155111: "0x0000000000000000000000000000000000000000"
  ]

  public static let accumulatorFactoryByChain: [UInt64: String] = [
    1: "0x0000000000000000000000000000000000000000",
    11155111: "0x0000000000000000000000000000000000000000"
  ]

  public static let protocolTreasuryByChain: [UInt64: String] = [
    1: "0x0000000000000000000000000000000000000000",
    11155111: "0x0000000000000000000000000000000000000000"
  ]

  public static func messengerAddress(chainId: UInt64) throws -> String {
    guard let value = messengerByChain[chainId] else {
      throw SmartAccountError.missingConfiguration(key: "messenger", chainId: chainId)
    }
    return value
  }

  public static func accumulatorFactoryAddress(chainId: UInt64) throws -> String {
    guard let value = accumulatorFactoryByChain[chainId] else {
      throw SmartAccountError.missingConfiguration(key: "accumulatorFactory", chainId: chainId)
    }
    return value
  }

  public static func protocolTreasuryAddress(chainId: UInt64) throws -> String {
    guard let value = protocolTreasuryByChain[chainId] else {
      throw SmartAccountError.missingConfiguration(key: "protocolTreasury", chainId: chainId)
    }
    return value
  }
}
