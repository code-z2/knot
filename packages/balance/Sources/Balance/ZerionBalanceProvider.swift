import Foundation
import RPC

public enum BalanceProviderError: LocalizedError {
  case invalidURL(String)
  case httpError(statusCode: Int)
  case apiError(message: String)
  case decodingFailed

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let url):
      return "Invalid balances API URL: \(url)"
    case .httpError(let statusCode):
      return "Balance API returned HTTP \(statusCode)."
    case .apiError(let message):
      return "Balance API error: \(message)"
    case .decodingFailed:
      return "Failed to decode balance response."
    }
  }
}

/// Fetches multichain wallet balances from Zerion positions endpoint and
/// groups them into canonical token buckets.
public actor ZerionBalanceProvider {
  private let session: URLSession

  private struct MutableChainBalance {
    let chainID: UInt64
    let chainName: String
    var balance: Decimal
    var valueUSD: Decimal
    var contractAddress: String
  }

  private struct MutableTokenGroup {
    let id: String
    let symbol: String
    var name: String
    var contractAddress: String
    var decimals: Int
    var isNative: Bool
    var totalBalance: Decimal
    var totalValueUSD: Decimal
    var quoteRate: Decimal
    var quoteRate24h: Decimal?
    var logoURL: URL?
    var chainBalances: [UInt64: MutableChainBalance]
  }

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func fetchBalances(
    walletAddress: String,
    positionsAPIURL: String,
    apiKey: String,
    supportedChainIDs: Set<UInt64>,
    includeTestnets: Bool,
    dustThresholdUSD: Decimal = 0.01,
    includeTrash: Bool = false,
    zerionChainMapping: ZerionChainMapping
  ) async throws -> [TokenBalance] {
    let endpointURLString = positionsAPIURL.replacingOccurrences(
      of: "{walletAddress}",
      with: walletAddress
    )

    guard var components = URLComponents(string: endpointURLString) else {
      throw BalanceProviderError.invalidURL(endpointURLString)
    }

    let zerionChainIDs = zerionChainMapping.zerionChainIDs(for: supportedChainIDs)

    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "currency", value: "usd"),
      URLQueryItem(name: "sort", value: "value"),
      URLQueryItem(name: "filter[trash]", value: includeTrash ? "no_filter" : "only_non_trash"),
      URLQueryItem(name: "filter[positions]", value: "no_filter"),
      URLQueryItem(name: "page[size]", value: "100"),
    ]

    if !zerionChainIDs.isEmpty {
      queryItems.append(
        URLQueryItem(name: "filter[chain_ids]", value: zerionChainIDs.joined(separator: ","))
      )
    }

    components.queryItems = queryItems

    guard let initialURL = components.url else {
      throw BalanceProviderError.invalidURL(endpointURLString)
    }

    var allPositions: [ZerionPositionItem] = []
    var nextURL: URL? = initialURL
    var pagesFetched = 0

    while let url = nextURL {
      pagesFetched += 1
      if pagesFetched > 20 {
        break
      }

      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue(Self.basicAuthValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")
      if includeTestnets {
        request.setValue("testnet", forHTTPHeaderField: "X-Env")
      }

      let (data, response) = try await session.data(for: request)

      if let httpResponse = response as? HTTPURLResponse,
        !(200...299).contains(httpResponse.statusCode)
      {
        if let body = String(data: data, encoding: .utf8)?.prefix(500) {
          throw BalanceProviderError.apiError(message: String(body))
        }
        throw BalanceProviderError.httpError(statusCode: httpResponse.statusCode)
      }

      let envelope: ZerionPositionsEnvelope
      do {
        envelope = try JSONDecoder().decode(ZerionPositionsEnvelope.self, from: data)
      } catch {
        throw BalanceProviderError.decodingFailed
      }

      allPositions.append(contentsOf: envelope.data)

      if let next = envelope.links?.next,
        let resolved = URL(string: next, relativeTo: url)?.absoluteURL
      {
        nextURL = resolved
      } else {
        nextURL = nil
      }
    }

    guard !allPositions.isEmpty else {
      return []
    }

    var groups: [String: MutableTokenGroup] = [:]

    for item in allPositions {
      guard let chainKey = item.relationships?.chain?.data?.id?.lowercased() else {
        continue
      }
      guard let chainID = zerionChainMapping.chainID(zerionChainID: chainKey) else {
        continue
      }
      guard supportedChainIDs.contains(chainID) else {
        continue
      }

      let quantity = item.attributes.quantity?.decimalValue ?? 0
      guard quantity > 0 else {
        continue
      }

      let rawSymbol = item.attributes.fungibleInfo?.symbol?.uppercased() ?? ""
      guard !rawSymbol.isEmpty else {
        continue
      }

      let canonicalSymbol = canonicalSymbol(for: rawSymbol)
      let groupKey = canonicalSymbol.lowercased()

      let valueUSD =
        item.attributes.value?.value
        ?? ((item.attributes.price?.value ?? 0) * quantity)
      let quoteRate =
        item.attributes.price?.value
        ?? (quantity > 0 ? (valueUSD / quantity) : 0)
      let quoteRate24h = quoteRate24hFromZerionChanges(
        currentRate: quoteRate,
        changes: item.attributes.changes
      )

      let chainDef = ChainRegistry.resolveOrFallback(chainID: chainID)
      let contractAddress = contractAddress(for: item, chainID: chainKey)
      let tokenName =
        item.attributes.fungibleInfo?.name ?? item.attributes.name
        ?? canonicalName(for: canonicalSymbol)
      let logoURL = URL(string: item.attributes.fungibleInfo?.icon?.url ?? "")

      var group =
        groups[groupKey]
        ?? MutableTokenGroup(
          id: groupKey,
          symbol: canonicalSymbol,
          name: tokenName,
          contractAddress: contractAddress,
          decimals: item.attributes.quantity?.decimals ?? 18,
          isNative: isLikelyNative(symbol: rawSymbol, contractAddress: contractAddress),
          totalBalance: 0,
          totalValueUSD: 0,
          quoteRate: 0,
          quoteRate24h: nil,
          logoURL: logoURL,
          chainBalances: [:]
        )

      group.totalBalance += quantity
      group.totalValueUSD += valueUSD

      if group.quoteRate == 0, quoteRate > 0 {
        group.quoteRate = quoteRate
      }
      if group.quoteRate24h == nil, let quoteRate24h, quoteRate24h > 0 {
        group.quoteRate24h = quoteRate24h
      }

      if group.logoURL == nil {
        group.logoURL = logoURL
      }
      if group.name.isEmpty {
        group.name = tokenName
      }
      if group.contractAddress.isEmpty {
        group.contractAddress = contractAddress
      }

      var perChain =
        group.chainBalances[chainID]
        ?? MutableChainBalance(
          chainID: chainID,
          chainName: chainDef.name,
          balance: 0,
          valueUSD: 0,
          contractAddress: contractAddress
        )

      perChain.balance += quantity
      perChain.valueUSD += valueUSD
      if perChain.contractAddress.isEmpty {
        perChain.contractAddress = contractAddress
      }
      group.chainBalances[chainID] = perChain

      groups[groupKey] = group
    }

    var balances: [TokenBalance] = []
    balances.reserveCapacity(groups.count)

    for group in groups.values {
      if group.totalValueUSD < dustThresholdUSD && group.totalValueUSD > 0 {
        continue
      }

      let chainBalances = group.chainBalances.values
        .map {
          ChainBalance(
            chainID: $0.chainID,
            chainName: $0.chainName,
            balance: $0.balance,
            valueUSD: $0.valueUSD,
            contractAddress: $0.contractAddress
          )
        }
        .sorted { $0.valueUSD > $1.valueUSD }

      balances.append(
        TokenBalance(
          id: group.id,
          symbol: group.symbol,
          name: group.name,
          contractAddress: group.contractAddress,
          decimals: group.decimals,
          isNative: group.isNative,
          totalBalance: group.totalBalance,
          totalValueUSD: group.totalValueUSD,
          quoteRate: group.quoteRate,
          quoteRate24h: group.quoteRate24h,
          logoURL: group.logoURL,
          chainBalances: chainBalances
        )
      )
    }

    balances.sort { $0.totalValueUSD > $1.totalValueUSD }
    return balances
  }

  private static func basicAuthValue(apiKey: String) -> String {
    let raw = "\(apiKey):"
    return "Basic \(Data(raw.utf8).base64EncodedString())"
  }

  private func contractAddress(for item: ZerionPositionItem, chainID: String) -> String {
    if let implementations = item.attributes.fungibleInfo?.implementations,
      let match = implementations.first(where: {
        $0.chainID?.lowercased() == chainID
      }),
      let address = match.address
    {
      return address
    }

    return ""
  }

  private func canonicalName(for symbol: String) -> String {
    switch symbol {
    case "ETH": return "Ethereum"
    case "POL": return "Polygon"
    default: return symbol
    }
  }

  private func isLikelyNative(symbol: String, contractAddress: String) -> Bool {
    if contractAddress.isEmpty {
      return true
    }
    return ["ETH", "POL", "MON", "BNB"].contains(symbol)
  }

  private func canonicalSymbol(for symbol: String) -> String {
    let upper = symbol.uppercased()
    let explicitAliases: [String: String] = [
      "ETH": "ETH",
      "WETH": "ETH",
      "WETH.E": "ETH",
      "POL": "POL",
      "MATIC": "POL",
      "WPOL": "POL",
      "WMATIC": "POL",
      "MON": "MON",
      "WMON": "MON",
      "BNB": "BNB",
      "WBNB": "BNB",
      "AVAX": "AVAX",
      "WAVAX": "AVAX",
    ]

    if let mapped = explicitAliases[upper] {
      return mapped
    }

    return upper
  }

  private func quoteRate24hFromZerionChanges(
    currentRate: Decimal,
    changes: ZerionPriceChanges?
  ) -> Decimal? {
    guard currentRate > 0 else { return nil }
    guard let percent1d = changes?.percent1d?.value else { return nil }

    // Zerion `percent_1d` is percent points (e.g. 2.5 for +2.5%).
    let denominator = 1 + (percent1d / 100)
    guard denominator > 0 else { return nil }

    return currentRate / denominator
  }
}
