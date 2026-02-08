import Foundation

/// Registry of bridge-supported tokens per chain.
///
/// "Flight assets" are tokens that Across can natively bridge between chains
/// (e.g. USDC, WETH). When the user's source or destination token isn't directly
/// bridgeable, the router pre/post-swaps through a flight asset.
public enum FlightAssets {

  public struct FlightAsset: Sendable, Equatable {
    public let symbol: String
    public let contractAddress: String
    public let decimals: Int

    public init(symbol: String, contractAddress: String, decimals: Int) {
      self.symbol = symbol
      self.contractAddress = contractAddress
      self.decimals = decimals
    }
  }

  /// Bridge-supported tokens keyed by chain ID.
  public static let byChain: [UInt64: [FlightAsset]] = [
    // --- Limited Testnet ---
    // Sepolia
    11_155_111: [
      .init(symbol: "WETH", contractAddress: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", decimals: 18)
    ],
    // Base Sepolia
    84_532: [
      .init(symbol: "WETH", contractAddress: "0x4200000000000000000000000000000000000006", decimals: 18)
    ],
    // Arbitrum Sepolia
    421_614: [
      .init(symbol: "WETH", contractAddress: "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73", decimals: 18)
    ],
    // --- Limited Mainnet ---
    // Base
    8_453: [
      .init(symbol: "USDC", contractAddress: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", decimals: 6),
      .init(symbol: "WETH", contractAddress: "0x4200000000000000000000000000000000000006", decimals: 18),
    ],
    // Arbitrum
    42_161: [
      .init(symbol: "USDC", contractAddress: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", decimals: 6),
      .init(symbol: "WETH", contractAddress: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", decimals: 18),
    ],
    // Optimism
    10: [
      .init(symbol: "USDC", contractAddress: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", decimals: 6),
      .init(symbol: "WETH", contractAddress: "0x4200000000000000000000000000000000000006", decimals: 18),
    ],
  ]

  /// Whether a token address is a bridge-supported flight asset on the given chain.
  public static func isFlightAsset(contractAddress: String, chainId: UInt64) -> Bool {
    guard let assets = byChain[chainId] else { return false }
    return assets.contains { $0.contractAddress.lowercased() == contractAddress.lowercased() }
  }

  /// Find a flight asset on a chain by symbol.
  public static func asset(symbol: String, chainId: UInt64) -> FlightAsset? {
    byChain[chainId]?.first { $0.symbol.uppercased() == symbol.uppercased() }
  }

  /// Returns the best flight asset available on **both** source and dest chains.
  /// Prefers USDC (stable, low slippage), falls back to WETH.
  public static func bestFlightAsset(
    sourceChain: UInt64,
    destChain: UInt64
  ) -> (source: FlightAsset, dest: FlightAsset)? {
    guard let sourceAssets = byChain[sourceChain],
      let destAssets = byChain[destChain]
    else {
      return nil
    }

    // Build a set of symbols available on both chains.
    let sourceSymbols = Set(sourceAssets.map(\.symbol))
    let destSymbols = Set(destAssets.map(\.symbol))
    let common = sourceSymbols.intersection(destSymbols)

    // Prefer USDC, then WETH.
    let preference = ["USDC", "WETH"]
    for symbol in preference {
      if common.contains(symbol),
        let src = sourceAssets.first(where: { $0.symbol == symbol }),
        let dst = destAssets.first(where: { $0.symbol == symbol })
      {
        return (source: src, dest: dst)
      }
    }

    // Fall back to any common symbol.
    if let symbol = common.first,
      let src = sourceAssets.first(where: { $0.symbol == symbol }),
      let dst = destAssets.first(where: { $0.symbol == symbol })
    {
      return (source: src, dest: dst)
    }

    return nil
  }
}
