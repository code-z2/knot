import Foundation

public enum ChainSupportMode: String, Sendable {
  case limitedTestnet = "LIMITED_TESTNET"
  case limitedMainnet = "LIMITED_MAINNET"
  case fullMainnet = "FULL_MAINNET"

  public var supportedChainsKey: String {
    switch self {
    case .limitedTestnet:
      return "SUPPORTED_CHAINS_LIMITED_TESTNET"
    case .limitedMainnet:
      return "SUPPORTED_CHAINS_LIMITED_MAINNET"
    case .fullMainnet:
      return "SUPPORTED_CHAINS_FULL_MAINNET"
    }
  }
}

public struct ChainSupportConfig: Sendable, Equatable {
  public let mode: ChainSupportMode
  public let chainIDs: [UInt64]

  public init(mode: ChainSupportMode, chainIDs: [UInt64]) {
    self.mode = mode
    self.chainIDs = chainIDs
  }
}

public enum ChainSupportRuntime {
  public static func resolveMode(
    bundle: Bundle = .main
  ) -> ChainSupportMode {
    let rawMode = resolveSetting(
      key: "CHAIN_SUPPORT_MODE",
      bundle: bundle
    ) ?? ChainSupportMode.limitedTestnet.rawValue

    return ChainSupportMode(rawValue: rawMode) ?? .limitedTestnet
  }

  public static func resolveSupportedChainIDs(
    mode: ChainSupportMode? = nil,
    bundle: Bundle = .main
  ) -> [UInt64] {
    let resolvedMode = mode ?? resolveMode(bundle: bundle)
    guard let rawValue = resolveSetting(key: resolvedMode.supportedChainsKey, bundle: bundle) else {
      return []
    }

    var output: [UInt64] = []
    var seen = Set<UInt64>()
    for token in rawValue.split(separator: ",") {
      guard let chainID = UInt64(token.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
      if seen.insert(chainID).inserted {
        output.append(chainID)
      }
    }
    return output
  }

  public static func resolveConfig(
    bundle: Bundle = .main
  ) -> ChainSupportConfig {
    let mode = resolveMode(bundle: bundle)
    let chainIDs = resolveSupportedChainIDs(mode: mode, bundle: bundle)
    return ChainSupportConfig(mode: mode, chainIDs: chainIDs)
  }

  private static func resolveSetting(
    key: String,
    bundle: Bundle
  ) -> String? {
    if let plist = bundle.object(forInfoDictionaryKey: key) as? String {
      let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
    }

    return nil
  }
}
