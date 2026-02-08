import Foundation

public enum BalanceProviderError: LocalizedError {
  case invalidURL(String)
  case httpError(statusCode: Int)
  case apiError(message: String)
  case decodingFailed

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let url):
      return "Invalid wallet API URL: \(url)"
    case .httpError(let statusCode):
      return "Balance API returned HTTP \(statusCode)."
    case .apiError(let message):
      return "Balance API error: \(message)"
    case .decodingFailed:
      return "Failed to decode balance response."
    }
  }
}

/// Fetches multichain token balances from the GoldRush (Covalent) API
/// and groups them by symbol.
public actor GoldRushBalanceProvider {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Fetches multichain balances for a wallet, grouped by token symbol.
  ///
  /// - Parameters:
  ///   - walletAddress: The 0x EOA address.
  ///   - apiURL: The resolved wallet API URL (with `{walletAddress}` already replaced).
  ///   - bearerToken: The GoldRush API key.
  ///   - dustThresholdUSD: Hide tokens below this value (default 0.01).
  /// - Returns: Grouped, sorted `[TokenBalance]`.
  public func fetchBalances(
    walletAddress: String,
    apiURL: String,
    bearerToken: String,
    dustThresholdUSD: Decimal = 0.01
  ) async throws -> [TokenBalance] {
    let urlString = apiURL.replacingOccurrences(
      of: "{walletAddress}",
      with: walletAddress
    )

    guard var components = URLComponents(string: urlString) else {
      throw BalanceProviderError.invalidURL(urlString)
    }

    // Append quote-currency query param.
    var queryItems = components.queryItems ?? []
    queryItems.append(URLQueryItem(name: "quote-currency", value: "USD"))
    components.queryItems = queryItems

    guard let url = components.url else {
      throw BalanceProviderError.invalidURL(urlString)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      throw BalanceProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: GoldRushEnvelope
    do {
      envelope = try JSONDecoder().decode(GoldRushEnvelope.self, from: data)
    } catch {
      throw BalanceProviderError.decodingFailed
    }

    if let errorMessage = envelope.errorMessage, envelope.error == true {
      throw BalanceProviderError.apiError(message: errorMessage)
    }

    guard let chainDataItems = envelope.data?.items else {
      return []
    }

    // Flatten all balance items across chains, annotating each with its chain info.
    var flatItems: [(item: GoldRushBalanceItem, chainID: UInt64, chainName: String)] = []
    for chainData in chainDataItems {
      let chainID = UInt64(chainData.chainId ?? 0)
      let chainName = chainData.chainName ?? "Unknown"
      for item in chainData.items ?? [] {
        flatItems.append((item: item, chainID: chainID, chainName: chainName))
      }
    }

    // Filter out spam and zero-balance items.
    let validItems = flatItems.filter { entry in
      guard entry.item.isSpam != true else { return false }
      guard let balanceStr = entry.item.balance, !balanceStr.isEmpty else { return false }
      guard balanceStr != "0" else { return false }
      guard let symbol = entry.item.contractTickerSymbol, !symbol.isEmpty else { return false }
      return true
    }

    // Group by symbol (case-insensitive).
    var groups: [String: [(item: GoldRushBalanceItem, chainID: UInt64, chainName: String)]] = [:]
    for entry in validItems {
      let key = entry.item.contractTickerSymbol!.lowercased()
      groups[key, default: []].append(entry)
    }

    // Build TokenBalance for each group.
    var balances: [TokenBalance] = []

    for (symbolKey, entries) in groups {
      var chainBalances: [ChainBalance] = []
      var totalBalance: Decimal = 0
      var totalValueUSD: Decimal = 0
      var bestQuoteRate: Decimal = 0
      var bestQuoteRate24h: Decimal?
      var bestLogoURL: URL?
      var bestName = ""
      var bestContractAddress = ""
      var bestDecimals = 18
      var isNative = false

      for entry in entries {
        let item = entry.item
        let decimals = item.contractDecimals ?? 18
        let rawBalance = Decimal(string: item.balance ?? "0") ?? 0
        let divisor = pow(Decimal(10), decimals)
        let humanBalance = rawBalance / divisor
        let valueUSD = Decimal(item.quote ?? 0)

        chainBalances.append(ChainBalance(
          chainID: entry.chainID,
          chainName: entry.chainName,
          balance: humanBalance,
          valueUSD: valueUSD,
          contractAddress: item.contractAddress ?? ""
        ))

        totalBalance += humanBalance
        totalValueUSD += valueUSD

        // Pick the first non-zero quote rate.
        if bestQuoteRate == 0, let rate = item.quoteRate, rate > 0 {
          bestQuoteRate = Decimal(rate)
        }

        // Pick the first non-nil 24h rate.
        if bestQuoteRate24h == nil, let rate24h = item.quoteRate24h, rate24h > 0 {
          bestQuoteRate24h = Decimal(rate24h)
        }

        // Pick the first non-nil logo URL.
        if bestLogoURL == nil,
           let logoString = item.logoUrls?.tokenLogoUrl,
           let url = URL(string: logoString) {
          bestLogoURL = url
        }

        // Pick the first non-empty name.
        if bestName.isEmpty, let name = item.contractName, !name.isEmpty {
          bestName = name
        }

        // Pick the first non-empty contract address.
        if bestContractAddress.isEmpty, let addr = item.contractAddress, !addr.isEmpty {
          bestContractAddress = addr
        }

        if item.isNativeToken == true {
          isNative = true
        }

        bestDecimals = decimals
      }

      // Dust filter.
      if totalValueUSD < dustThresholdUSD && totalValueUSD > 0 {
        continue
      }

      let symbol = entries.first?.item.contractTickerSymbol ?? symbolKey

      balances.append(TokenBalance(
        id: symbolKey,
        symbol: symbol,
        name: bestName,
        contractAddress: bestContractAddress,
        decimals: bestDecimals,
        isNative: isNative,
        totalBalance: totalBalance,
        totalValueUSD: totalValueUSD,
        quoteRate: bestQuoteRate,
        quoteRate24h: bestQuoteRate24h,
        logoURL: bestLogoURL,
        chainBalances: chainBalances
      ))
    }

    // Sort descending by total USD value.
    balances.sort { $0.totalValueUSD > $1.totalValueUSD }

    return balances
  }

  /// Raises `Decimal(10)` to the given integer power.
  private func pow(_ base: Decimal, _ exponent: Int) -> Decimal {
    guard exponent >= 0 else { return 1 }
    if exponent == 0 { return 1 }
    var result = base
    for _ in 1..<exponent {
      result *= base
    }
    return result
  }
}
