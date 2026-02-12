import Foundation

public struct ChainDefinition: Sendable, Hashable, Identifiable {
  public let chainID: UInt64
  public let slug: String
  public let name: String
  public let assetName: String
  public let keywords: [String]
  public let rpcURL: String?
  public let explorerBaseURL: String?
  public let supportsBundler: Bool
  public let supportsPaymaster: Bool
  /// GoldRush/Covalent chain name for per-chain API calls (differs from Alchemy slug for some chains).
  public let goldRushChainName: String?

  public var id: UInt64 { chainID }

  public init(
    chainID: UInt64,
    slug: String,
    name: String,
    assetName: String,
    keywords: [String],
    rpcURL: String?,
    explorerBaseURL: String?,
    supportsBundler: Bool = false,
    supportsPaymaster: Bool = false,
    goldRushChainName: String? = nil
  ) {
    self.chainID = chainID
    self.slug = slug
    self.name = name
    self.assetName = assetName
    self.keywords = keywords
    self.rpcURL = rpcURL
    self.explorerBaseURL = explorerBaseURL
    self.supportsBundler = supportsBundler
    self.supportsPaymaster = supportsPaymaster
    self.goldRushChainName = goldRushChainName
  }

  public func makeEndpoints(config: RPCEndpointBuilderConfig) -> ChainEndpoints? {
    let templatedRPCURL = makeURL(
      chainID: chainID,
      slug: slug,
      template: config.jsonRPCURLTemplate,
      apiKey: config.jsonRPCAPIKey
    )
    let resolvedRPCURL = firstNonEmpty(templatedRPCURL, rpcURL ?? "")
    guard !resolvedRPCURL.isEmpty else {
      return nil
    }

    let bundlerURL =
      supportsBundler
      ? makeURL(
        chainID: chainID,
        slug: slug,
        template: config.bundlerURLTemplate,
        apiKey: config.bundlerAPIKey
      )
      : ""
    let paymasterURL =
      supportsPaymaster
      ? makeURL(
        chainID: chainID,
        slug: slug,
        template: config.paymasterURLTemplate,
        apiKey: config.paymasterAPIKey
      )
      : ""
    let walletAPIURL = makeURL(
      chainID: chainID,
      slug: slug,
      template: config.walletAPIURLTemplate
    )
    let addressActivityAPIURL = makeURL(
      chainID: chainID,
      slug: slug,
      template: config.addressActivityAPIURLTemplate
    )
    return ChainEndpoints(
      rpcURL: resolvedRPCURL,
      bundlerURL: bundlerURL,
      paymasterURL: paymasterURL,
      walletAPIURL: walletAPIURL,
      walletAPIBearerToken: config.walletAPIKey,
      addressActivityAPIURL: addressActivityAPIURL,
      addressActivityAPIBearerToken: config.addressActivityAPIKey
    )
  }

  public func addressURL(address: String) -> URL? {
    guard let explorerBaseURL else { return nil }
    let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    return URL(string: "\(explorerBaseURL)/address/\(normalized)")
  }

  public func transactionURL(transactionHash: String) -> URL? {
    guard let explorerBaseURL else { return nil }
    let normalized = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    return URL(string: "\(explorerBaseURL)/tx/\(normalized)")
  }
}

public enum ChainRegistry {
  public static let known: [ChainDefinition] = [
    .init(
      chainID: 1,
      slug: "eth-mainnet",
      name: "Ethereum",
      assetName: "ethereum",
      keywords: ["eth", "mainnet"],
      rpcURL: nil,
      explorerBaseURL: "https://etherscan.io",
      goldRushChainName: "eth-mainnet"
    ),
    .init(
      chainID: 11_155_111,
      slug: "eth-sepolia",
      name: "Sepolia",
      assetName: "ethereum",
      keywords: ["eth", "testnet"],
      rpcURL: nil,
      explorerBaseURL: "https://sepolia.etherscan.io",
      supportsBundler: true,
      supportsPaymaster: true,
      goldRushChainName: "eth-sepolia"
    ),
    .init(
      chainID: 8_453,
      slug: "base-mainnet",
      name: "Base",
      assetName: "base",
      keywords: ["coinbase"],
      rpcURL: nil,
      explorerBaseURL: "https://basescan.org",
      supportsBundler: true,
      supportsPaymaster: true,
      goldRushChainName: "base-mainnet"
    ),
    .init(
      chainID: 84_532,
      slug: "base-sepolia",
      name: "Base Sepolia",
      assetName: "base",
      keywords: ["base", "testnet"],
      rpcURL: nil,
      explorerBaseURL: "https://sepolia.basescan.org",
      supportsBundler: true,
      supportsPaymaster: true,
      goldRushChainName: "base-sepolia-testnet"
    ),
    .init(
      chainID: 42_161,
      slug: "arb-mainnet",
      name: "Arbitrum",
      assetName: "arbitrum",
      keywords: ["arb"],
      rpcURL: nil,
      explorerBaseURL: "https://arbiscan.io",
      supportsBundler: true,
      goldRushChainName: "arb-mainnet"
    ),
    .init(
      chainID: 421_614,
      slug: "arb-sepolia",
      name: "Arbitrum Sepolia",
      assetName: "arbitrum",
      keywords: ["arb", "testnet"],
      rpcURL: nil,
      explorerBaseURL: "https://sepolia.arbiscan.io",
      supportsBundler: true,
      goldRushChainName: "arbitrum-sepolia"
    ),
    .init(
      chainID: 10,
      slug: "opt-mainnet",
      name: "Optimism",
      assetName: "optimism",
      keywords: ["op"],
      rpcURL: nil,
      explorerBaseURL: "https://optimistic.etherscan.io",
      supportsBundler: true
    ),
    .init(
      chainID: 137,
      slug: "polygon-mainnet",
      name: "Polygon",
      assetName: "polygon",
      keywords: ["matic", "pol"],
      rpcURL: nil,
      explorerBaseURL: "https://polygonscan.com",
      supportsBundler: true,
      supportsPaymaster: true,
      goldRushChainName: "matic-mainnet"
    ),
    .init(
      chainID: 56,
      slug: "bnb-mainnet",
      name: "BNB Smart Chain",
      assetName: "bnb-smart-chain",
      keywords: ["bnb", "bsc", "binance"],
      rpcURL: nil,
      explorerBaseURL: "https://bscscan.com"
    ),
    .init(
      chainID: 81_457,
      slug: "blast-mainnet",
      name: "Blast",
      assetName: "blast",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://blastscan.io"
    ),
    .init(
      chainID: 59_144,
      slug: "linea-mainnet",
      name: "Linea",
      assetName: "linea",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://explorer.linea.build"
    ),
    .init(
      chainID: 1_136,
      slug: "lisk",
      name: "Lisk",
      assetName: "lisk",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://blockscout.lisk.com"
    ),
    .init(
      chainID: 3_443,
      slug: "mode-mainnet",
      name: "Mode",
      assetName: "mode",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://explorer.mode.network"
    ),
    .init(
      chainID: 10_143,
      slug: "monad-testnet",
      name: "Monad",
      assetName: "monad",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://testnet.monadexplorer.com"
    ),
    .init(
      chainID: 9_742,
      slug: "plasma-mainnet",
      name: "Plasma",
      assetName: "plasma",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://plasmascan.to"
    ),
    .init(
      chainID: 534_352,
      slug: "scroll-mainnet",
      name: "Scroll",
      assetName: "scroll",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://scroll.blockscout.com"
    ),
    .init(
      chainID: 1_868,
      slug: "soneium-mainnet",
      name: "Soneium",
      assetName: "soneium",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://soneium.blockscout.com"
    ),
    .init(
      chainID: 130,
      slug: "unichain-mainnet",
      name: "Unichain",
      assetName: "unichain",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://unichain.blockscout.com"
    ),
    .init(
      chainID: 480,
      slug: "worldchain-mainnet",
      name: "World Chain",
      assetName: "world-chain",
      keywords: ["world"],
      rpcURL: nil,
      explorerBaseURL: "https://worldchain-mainnet.explorer.alchemy.com"
    ),
    .init(
      chainID: 324,
      slug: "zksync-mainnet",
      name: "zkSync",
      assetName: "zksync",
      keywords: ["zk"],
      rpcURL: nil,
      explorerBaseURL: "https://zksync.blockscout.com"
    ),
    .init(
      chainID: 7_777_777,
      slug: "zora-mainnet",
      name: "Zora",
      assetName: "zora",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://explorer.zora.energy"
    ),
    .init(
      chainID: 9_999,
      slug: "hyperliquid-mainnet",
      name: "HyperEVM",
      assetName: "hyperevm",
      keywords: ["hyper"],
      rpcURL: nil,
      explorerBaseURL: "https://hyperevmscan.io"
    ),
    .init(
      chainID: 57_073,
      slug: "ink-mainnet",
      name: "Ink",
      assetName: "ink",
      keywords: [],
      rpcURL: nil,
      explorerBaseURL: "https://explorer.inkonchain.com"
    ),
  ]

  private static let knownByChainID: [UInt64: ChainDefinition] = Dictionary(
    uniqueKeysWithValues: known.map { ($0.chainID, $0) }
  )

  public static func resolve(chainID: UInt64) -> ChainDefinition? {
    knownByChainID[chainID]
  }

  public static func resolveOrFallback(chainID: UInt64) -> ChainDefinition {
    if let known = resolve(chainID: chainID) {
      return known
    }
    return ChainDefinition(
      chainID: chainID,
      slug: "chain-\(chainID)",
      name: "Chain \(chainID)",
      assetName: "ethereum",
      keywords: ["custom", String(chainID)],
      rpcURL: nil,
      explorerBaseURL: nil
    )
  }

  public static func getChains(
    bundle: Bundle = .main
  ) -> [ChainDefinition] {
    let configuredChainIDs = ChainSupportRuntime.resolveSupportedChainIDs(bundle: bundle)
    guard !configuredChainIDs.isEmpty else { return [] }
    return configuredChainIDs.map(resolveOrFallback(chainID:))
  }
}

private func firstNonEmpty(_ candidates: String...) -> String {
  for candidate in candidates {
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      return trimmed
    }
  }
  return ""
}

private func makeURL(chainID: UInt64, slug: String, template: String) -> String {
  makeURL(chainID: chainID, slug: slug, template: template, apiKey: "")
}

private func makeURL(chainID: UInt64, slug: String, template: String, apiKey: String) -> String {
  var resolved = template.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !resolved.isEmpty else { return "" }

  resolved = resolved.replacingOccurrences(of: "{chainId}", with: String(chainID))
  resolved = resolved.replacingOccurrences(of: "{slug}", with: slug)

  if resolved.contains("{apiKey}") {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return "" }
    resolved = resolved.replacingOccurrences(of: "{apiKey}", with: key)
  }

  return resolved
}
