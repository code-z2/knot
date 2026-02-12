import Foundation

public enum AAConstants {
  // Single addresses — same on all chains (deterministic CREATE2 deployment).
  public static let accumulatorFactoryAddress = "0xb329c298dfa2f7fce4de1329d8cd1dd1dea9f41f"

  // Across V4 SpokePool addresses by chain ID.
  public static let spokePoolByChain: [UInt64: String] = [
    // Limited Testnet
    11_155_111: "0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662",  // Sepolia
    84_532: "0x82B564983aE7274c86695917BBf8C99ECb6F0F8F",  // Base Sepolia
    421_614: "0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75",  // Arbitrum Sepolia
    // Limited Mainnet
    8_453: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",  // Base
    42_161: "0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A",  // Arbitrum
    10: "0x6f26Bf09B1C792e3228e5467807a900A503c0281",  // Optimism
    137: "0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096",  // Polygon
  ]

  // Wrapped native token by chain ID (for account initialize config).
  public static let wrappedNativeTokenByChain: [UInt64: String] = [
    // Limited Testnet
    11_155_111: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",  // Sepolia WETH
    84_532: "0x4200000000000000000000000000000000000006",  // Base Sepolia WETH
    421_614: "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73",  // Arbitrum Sepolia WETH
    // Limited Mainnet
    8_453: "0x4200000000000000000000000000000000000006",  // Base WETH
    42_161: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",  // Arbitrum WETH
    10: "0x4200000000000000000000000000000000000006",  // Optimism WETH
    137: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",  // Polygon WETH
  ]

  // Legacy alias kept to avoid breaking existing callers during migration.
  public static let messengerByChain: [UInt64: String] = spokePoolByChain

  public static func spokePoolAddress(chainId: UInt64) throws -> String {
    guard let value = spokePoolByChain[chainId] else {
      throw SmartAccountError.missingConfiguration(key: "spokePool", chainId: chainId)
    }
    return value
  }

  // Legacy alias kept to avoid breaking existing callers.
  public static func messengerAddress(chainId: UInt64) throws -> String {
    try spokePoolAddress(chainId: chainId)
  }

  public static func wrappedNativeTokenAddress(chainId: UInt64) throws -> String {
    guard let value = wrappedNativeTokenByChain[chainId] else {
      throw SmartAccountError.missingConfiguration(key: "wrappedNativeToken", chainId: chainId)
    }
    return value
  }
}
