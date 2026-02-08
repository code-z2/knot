import Foundation

public enum AAConstants {
  public static let entryPointV09 = "0x433709009B8330FDa32311DF1C2AFA402eD8D009"

  // Single addresses — same on all chains (deterministic CREATE2 deployment).
  // TODO: Fill after deterministic deployment.
  public static let accumulatorFactoryAddress = "0xb329c298dfa2f7fce4de1329d8cd1dd1dea9f41f"
  public static let protocolTreasuryAddress = "0xD981029dF93894fCEdb5d116D84cC0e9e7C679CA"

  // Across V4 SpokePool addresses by chain ID (messenger for accumulator).
  public static let messengerByChain: [UInt64: String] = [
    // Limited Testnet
    11_155_111: "0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662",  // Sepolia
    84_532: "0x82B564983aE7274c86695917BBf8C99ECb6F0F8F",  // Base Sepolia
    421_614: "0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75",  // Arbitrum Sepolia
    // Limited Mainnet
    8_453: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",  // Base
    42_161: "0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A",  // Arbitrum
    10: "0x6f26Bf09B1C792e3228e5467807a900A503c0281",  // Optimism
  ]

  public static func messengerAddress(chainId: UInt64) throws -> String {
    guard let value = messengerByChain[chainId] else {
      throw SmartAccountError.missingConfiguration(key: "messenger", chainId: chainId)
    }
    return value
  }
}
