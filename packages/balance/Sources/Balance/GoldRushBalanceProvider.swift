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

/// Fetches multichain token balances from the GoldRush allchains endpoint
/// and groups them by symbol.
public actor GoldRushBalanceProvider {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Fetches balances for a wallet across all chains via the single allchains endpoint.
  ///
  /// Uses `GET /v1/allchains/address/{wallet}/balances/?quote-currency=USD&no-spam=true`
  /// which returns balances grouped by chain in a single response.
  ///
  /// - Parameters:
  ///   - walletAddress: The 0x EOA address.
  ///   - walletAPIURL: The allchains balance URL template containing `{walletAddress}`.
  ///   - bearerToken: GoldRush API key.
  ///   - dustThresholdUSD: Hide tokens below this value (default 0.01).
  /// - Returns: Grouped, sorted `[TokenBalance]`.
  public func fetchBalances(
    walletAddress: String,
    walletAPIURL: String,
    bearerToken: String,
    dustThresholdUSD: Decimal = 0.01
  ) async throws -> [TokenBalance] {
    let urlString = walletAPIURL.replacingOccurrences(
      of: "{walletAddress}",
      with: walletAddress
    )

    guard var components = URLComponents(string: urlString) else {
      throw BalanceProviderError.invalidURL(urlString)
    }

    var queryItems = components.queryItems ?? []
    queryItems.append(contentsOf: [
      URLQueryItem(name: "quote-currency", value: "USD"),
      URLQueryItem(name: "no-spam", value: "true"),
    ])
    components.queryItems = queryItems

    guard let url = components.url else {
      throw BalanceProviderError.invalidURL(urlString)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    print("[GoldRushBalance] GET \(url.absoluteString)")
    let (data, response) = try await session.data(for: request)

    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    print("[GoldRushBalance] HTTP \(statusCode), \(data.count) bytes")

    if let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      if let body = String(data: data, encoding: .utf8)?.prefix(500) {
        print("[GoldRushBalance] ❌ error body: \(body)")
      }
      throw BalanceProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: GoldRushEnvelope
    do {
      envelope = try JSONDecoder().decode(GoldRushEnvelope.self, from: data)
    } catch {
      print("[GoldRushBalance] ❌ decode failed: \(error)")
      if let body = String(data: data, encoding: .utf8)?.prefix(500) {
        print("[GoldRushBalance] raw response: \(body)")
      }
      throw BalanceProviderError.decodingFailed
    }

    if let errorMessage = envelope.errorMessage, envelope.error == true {
      print("[GoldRushBalance] ❌ API error: \(errorMessage)")
      throw BalanceProviderError.apiError(message: errorMessage)
    }

    guard let flatItems = envelope.data?.items, !flatItems.isEmpty else {
      print("[GoldRushBalance] ⚠️ envelope.data.items is nil or empty — returning empty")
      return []
    }

    print("[GoldRushBalance] \(flatItems.count) item(s) in response")

    // Filter out spam and zero-balance items.
    let validItems = flatItems.filter { item in
      guard item.isSpam != true else {
        print("[GoldRushBalance] ⚠️ Filtered spam: \(item.contractTickerSymbol ?? "???")")
        return false
      }
      guard let balanceStr = item.balance, !balanceStr.isEmpty else {
        print("[GoldRushBalance] ⚠️ Filtered empty balance: \(item.contractTickerSymbol ?? "???")")
        return false
      }
      guard balanceStr != "0" else {
        // frequent, so maybe don't log every single one unless debugging deep
        // print("[GoldRushBalance] ⚠️ Filtered zero balance: \(item.contractTickerSymbol ?? "???")")
        return false
      }
      guard let symbol = item.contractTickerSymbol, !symbol.isEmpty else {
        print("[GoldRushBalance] ⚠️ Filtered missing symbol: Balance=\(balanceStr)")
        return false
      }
      return true
    }

    print("[GoldRushBalance] \(validItems.count) valid item(s) after filter")

    // Group by symbol (case-insensitive).
    var groups: [String: [GoldRushBalanceItem]] = [:]
    for item in validItems {
      let key = item.contractTickerSymbol!.lowercased()
      groups[key, default: []].append(item)
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

      for item in entries {
        let decimals = item.contractDecimals ?? 18
        let rawBalance = Decimal(string: item.balance ?? "0") ?? 0
        let divisor = pow(Decimal(10), decimals)
        let humanBalance = rawBalance / divisor
        let valueUSD = Decimal(item.quote ?? 0)

        chainBalances.append(
          ChainBalance(
            chainID: UInt64(item.chainId ?? 0),
            chainName: item.chainName ?? "Unknown",
            balance: humanBalance,
            valueUSD: valueUSD,
            contractAddress: item.contractAddress ?? ""
          ))

        totalBalance += humanBalance
        totalValueUSD += valueUSD

        if bestQuoteRate == 0, let rate = item.quoteRate, rate > 0 {
          bestQuoteRate = Decimal(rate)
        }
        if bestQuoteRate24h == nil, let rate24h = item.quoteRate24h, rate24h > 0 {
          bestQuoteRate24h = Decimal(rate24h)
        }
        if bestLogoURL == nil,
          let logoString = item.logoUrls?.tokenLogoUrl,
          let url = URL(string: logoString)
        {
          bestLogoURL = url
        } else if bestLogoURL == nil && item.isNativeToken == true {
          print(
            "[GoldRushBalance] ⚠️ Missing logo for native token: \(item.contractTickerSymbol ?? "?") on chain \(item.chainId ?? 0). logoUrls: \(String(describing: item.logoUrls))"
          )
        }
        if bestName.isEmpty, let name = item.contractName, !name.isEmpty {
          bestName = name
        }
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

      let symbol = entries.first?.contractTickerSymbol ?? symbolKey

      balances.append(
        TokenBalance(
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
