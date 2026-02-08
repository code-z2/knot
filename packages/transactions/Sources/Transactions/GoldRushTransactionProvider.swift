import Foundation
import RPC

public enum TransactionProviderError: LocalizedError {
  case invalidURL(String)
  case httpError(statusCode: Int)
  case apiError(message: String)
  case decodingFailed

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let url):
      return "Invalid transactions API URL: \(url)"
    case .httpError(let statusCode):
      return "Transactions API returned HTTP \(statusCode)."
    case .apiError(let message):
      return "Transactions API error: \(message)"
    case .decodingFailed:
      return "Failed to decode transactions response."
    }
  }
}

/// Fetches multichain transaction history from the GoldRush allchains
/// transactions endpoint, classifies each tx, and returns grouped sections.
public actor GoldRushTransactionProvider {
  private let session: URLSession

  // MARK: - Event topic0 constants

  /// keccak256("CrossChainInitiated()")
  /// Parameter-less marker event emitted by executeChainCalls on source chains.
  static let crossChainInitiatedTopic0 =
    "0xa24e3cfa2b7e03a4e76e0e2eb76e25daea1cf8d64498fb3720d44e56a847e8c0"

  /// keccak256("MultiChainIntentExecuted(bytes32,address,address,address,uint256,uint256[])")
  /// Emitted by Accumulator on successful destination-chain execution.
  static let multiChainIntentExecutedTopic0 =
    "0xf2d7aa0e0cf2e24ade6c3a9e59b9a5a789f6a9cb9f5e6a2d3c8bce65a9a6d4c1"

  /// keccak256("Transfer(address,address,uint256)")
  static let transferTopic0 =
    "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Fetch recent transactions for the given wallet (and optional accumulator) via the
  /// allchains endpoint: `GET /v1/allchains/transactions/{address}/`.
  ///
  /// - Parameters:
  ///   - walletAddress: The user's EOA address.
  ///   - accumulatorAddress: The user's Accumulator address (same on all chains). Nil if unresolved.
  ///   - transactionsURLBase: The allchains transactions base URL (e.g. `https://api.covalenthq.com/v1/allchains/transactions/`).
  ///   - apiKey: GoldRush API key.
  /// - Returns: Classified, date-grouped transaction sections.
  public func fetchTransactions(
    walletAddress: String,
    accumulatorAddress: String?,
    transactionsURLBase: String,
    apiKey: String
  ) async throws -> TransactionPage {
    // Fetch EOA transactions
    var allItems = try await fetchAllchains(
      address: walletAddress,
      transactionsURLBase: transactionsURLBase,
      apiKey: apiKey
    )

    // If accumulator address exists, also fetch its txs
    if let acc = accumulatorAddress, !acc.isEmpty {
      let accItems = try await fetchAllchains(
        address: acc,
        transactionsURLBase: transactionsURLBase,
        apiKey: apiKey
      )
      allItems.append(contentsOf: accItems)
    }

    print("[GoldRushTx] \(allItems.count) raw tx item(s)")

    let userAddr = walletAddress.lowercased()
    let accAddr = accumulatorAddress?.lowercased()

    // Classify and filter
    var records: [TransactionRecord] = []

    for item in allItems {
      // Detect cross-chain suppression via raw_log_topics
      if hasCrossChainInitiatedEvent(item) {
        continue  // suppress source-chain scatter txs
      }

      let record = classify(item: item, userAddress: userAddr, accumulatorAddress: accAddr)
      records.append(record)
    }

    // Sort by date descending before grouping
    records.sort { $0.blockSignedAt > $1.blockSignedAt }

    // Group by date
    let sections = groupByDate(records)

    return TransactionPage(
      sections: sections,
      cursorAfter: nil,
      hasMore: false
    )
  }

  // MARK: - Allchains fetch

  /// Fetch recent transactions via the allchains endpoint.
  private func fetchAllchains(
    address: String,
    transactionsURLBase: String,
    apiKey: String
  ) async throws -> [GoldRushTxItem] {
    let urlString = "\(transactionsURLBase)"

    guard var components = URLComponents(string: urlString) else {
      throw TransactionProviderError.invalidURL(urlString)
    }

    components.queryItems = [
      URLQueryItem(name: "quote-currency", value: "USD"),
      // The allchains/transactions endpoint requires 'addresses' as a query param,
      // not as part of the path.
      URLQueryItem(name: "addresses", value: address),
    ]

    guard let url = components.url else {
      throw TransactionProviderError.invalidURL(urlString)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    print("[GoldRushTx] GET \(url.absoluteString)")
    let (data, response) = try await session.data(for: request)

    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    print("[GoldRushTx] HTTP \(statusCode), \(data.count) bytes")

    if let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      if let body = String(data: data, encoding: .utf8)?.prefix(500) {
        print("[GoldRushTx] ❌ error body: \(body)")
      }
      throw TransactionProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: GoldRushTxEnvelope
    do {
      envelope = try JSONDecoder().decode(GoldRushTxEnvelope.self, from: data)
    } catch {
      print("[GoldRushTx] ❌ decode failed: \(error)")
      if let body = String(data: data, encoding: .utf8)?.prefix(500) {
        print("[GoldRushTx] raw response: \(body)")
      }
      throw TransactionProviderError.decodingFailed
    }

    if let errorMessage = envelope.errorMessage, envelope.error == true {
      print("[GoldRushTx] ❌ API error: \(errorMessage)")
      throw TransactionProviderError.apiError(message: errorMessage)
    }

    let items = envelope.data?.items ?? []
    print("[GoldRushTx] \(items.count) tx(s)")
    return items
  }

  // MARK: - Classification

  private func hasCrossChainInitiatedEvent(_ item: GoldRushTxItem) -> Bool {
    guard let logs = item.logEvents else { return false }
    return logs.contains { log in
      guard let topics = log.rawLogTopics, let topic0 = topics.first else { return false }
      return topic0.lowercased() == Self.crossChainInitiatedTopic0.lowercased()
    }
  }

  private func hasMultiChainIntentExecutedEvent(_ item: GoldRushTxItem) -> Bool {
    guard let logs = item.logEvents else { return false }
    return logs.contains { log in
      guard let topics = log.rawLogTopics, let topic0 = topics.first else { return false }
      return topic0.lowercased() == Self.multiChainIntentExecutedTopic0.lowercased()
    }
  }

  private func classify(
    item: GoldRushTxItem,
    userAddress: String,
    accumulatorAddress: String?
  ) -> TransactionRecord {
    let chainId = UInt64(item.chainId ?? "0") ?? 0
    let chainName = item.chainName ?? "Unknown"
    let txHash = item.txHash ?? ""
    let from = item.fromAddress?.lowercased() ?? ""
    let to = item.toAddress?.lowercased() ?? ""
    let successful = item.successful ?? false
    let valueQuote = Decimal(item.valueQuote ?? 0)
    let gasQuote = Decimal(item.gasQuote ?? 0)
    let blockDate = parseDate(item.blockSignedAt)
    let chainDef = ChainRegistry.resolveOrFallback(chainID: chainId)

    // Check for multichain intent executed (accumulator destination tx)
    if hasMultiChainIntentExecutedEvent(item) {
      let sourceChainAssets = extractSourceChainAssets(item)
      let recipient = extractMultichainRecipient(item)
      let (symbol, amountText, usdValue) = extractMultichainValue(item)

      return TransactionRecord(
        id: "mc:\(chainId):\(txHash)",
        status: successful ? .success : .failed,
        variant: .multichain,
        chainId: chainId,
        chainName: chainName,
        txHash: txHash,
        fromAddress: from,
        toAddress: to,
        blockSignedAt: blockDate,
        valueQuoteUSD: usdValue ?? valueQuote,
        assetAmountText: amountText ?? "",
        tokenSymbol: symbol ?? "ETH",
        gasQuoteUSD: gasQuote,
        networkAssetName: chainDef.assetName,
        accumulatedFromNetworkAssetNames: sourceChainAssets,
        multichainRecipient: recipient
      )
    }

    // Find the primary Transfer event for value extraction.
    // Check both the user's EOA and accumulator address as possible participants.
    let transfer = findPrimaryTransfer(
      item: item, userAddress: userAddress, accumulatorAddress: accumulatorAddress)

    let tokenSymbol = transfer?.symbol ?? (valueQuote > 0 ? "ETH" : "")
    let amountText = transfer?.amountText ?? ""
    let transferUSD = transfer?.usdValue ?? valueQuote

    // Build the set of addresses we consider "ours"
    let ownedAddresses: Set<String> = {
      var addrs: Set<String> = [userAddress]
      if let acc = accumulatorAddress { addrs.insert(acc) }
      return addrs
    }()

    // Classify variant
    let variant: TxRecordVariant
    if transfer != nil && transfer!.direction == .inbound {
      variant = .received
    } else if transfer != nil && transfer!.direction == .outbound {
      variant = .sent
    } else if ownedAddresses.contains(to) && valueQuote > 0 {
      variant = .received
    } else if ownedAddresses.contains(from) && (valueQuote > 0 || transfer != nil) {
      variant = .sent
    } else {
      variant = .contract
    }

    return TransactionRecord(
      id: "\(chainId):\(txHash)",
      status: successful ? .success : .failed,
      variant: variant,
      chainId: chainId,
      chainName: chainName,
      txHash: txHash,
      fromAddress: item.fromAddress ?? "",
      toAddress: item.toAddress ?? "",
      blockSignedAt: blockDate,
      valueQuoteUSD: transferUSD,
      assetAmountText: amountText,
      tokenSymbol: tokenSymbol,
      gasQuoteUSD: gasQuote,
      networkAssetName: chainDef.assetName
    )
  }

  // MARK: - Transfer extraction

  private enum TransferDirection {
    case inbound
    case outbound
  }

  private struct TransferInfo {
    let direction: TransferDirection
    let symbol: String
    let amountText: String
    let usdValue: Decimal
  }

  /// Find the primary ERC-20 Transfer event relevant to the user.
  /// Checks both the user's EOA address and accumulator address.
  private func findPrimaryTransfer(
    item: GoldRushTxItem,
    userAddress: String,
    accumulatorAddress: String?
  ) -> TransferInfo? {
    guard let logs = item.logEvents else { return nil }

    // All addresses we consider "ours"
    var ownedAddresses: Set<String> = [userAddress]
    if let acc = accumulatorAddress { ownedAddresses.insert(acc) }

    for log in logs {
      guard let topics = log.rawLogTopics,
        let topic0 = topics.first
      else { continue }

      guard topic0.lowercased() == Self.transferTopic0.lowercased(),
        topics.count >= 3
      else { continue }

      // topic1 = from (indexed, padded to 32 bytes), topic2 = to (indexed)
      let fromTopic = extractAddress(from: topics[1])
      let toTopic = extractAddress(from: topics[2])

      let symbol = log.senderContractTickerSymbol ?? ""
      let decimals = log.senderContractDecimals ?? 18

      // Decode amount from raw_log_data
      let amount = decodeUint256(from: log.rawLogData, decimals: decimals)
      let amountText = formatAmount(amount, symbol: symbol)

      // Estimate USD value (use the tx-level value_quote as approximation)
      let usdValue = Decimal(item.valueQuote ?? 0)

      if ownedAddresses.contains(toTopic) {
        return TransferInfo(
          direction: .inbound, symbol: symbol, amountText: amountText, usdValue: usdValue)
      } else if ownedAddresses.contains(fromTopic) {
        return TransferInfo(
          direction: .outbound, symbol: symbol, amountText: amountText, usdValue: usdValue)
      }
    }

    return nil
  }

  // MARK: - Multichain value extraction

  private func extractSourceChainAssets(_ item: GoldRushTxItem) -> [String] {
    return []
  }

  private func extractMultichainRecipient(_ item: GoldRushTxItem) -> String? {
    guard let logs = item.logEvents else { return nil }
    for log in logs {
      guard let topics = log.rawLogTopics,
        let topic0 = topics.first,
        topic0.lowercased() == Self.multiChainIntentExecutedTopic0.lowercased(),
        let rawData = log.rawLogData, rawData.count >= 66
      else { continue }
      return extractAddress(from: String(rawData.prefix(66)))
    }
    return nil
  }

  private func extractMultichainValue(_ item: GoldRushTxItem) -> (
    symbol: String?, amountText: String?, usdValue: Decimal?
  ) {
    let usd = item.valueQuote.map { Decimal($0) }
    return (nil, nil, usd)
  }

  // MARK: - Helpers

  /// Extract a 20-byte address from a 32-byte hex-encoded topic.
  private func extractAddress(from topic: String) -> String {
    let hex = topic.hasPrefix("0x") ? String(topic.dropFirst(2)) : topic
    guard hex.count >= 40 else { return "" }
    let addressHex = String(hex.suffix(40))
    return "0x\(addressHex)".lowercased()
  }

  /// Decode a uint256 from the first 32 bytes of raw log data and apply decimals.
  private func decodeUint256(from rawData: String?, decimals: Int) -> Decimal {
    guard let rawData else { return 0 }
    let hex = rawData.hasPrefix("0x") ? String(rawData.dropFirst(2)) : rawData
    guard hex.count >= 64 else { return 0 }
    let first64 = String(hex.prefix(64))

    var result: Decimal = 0
    for char in first64 {
      guard let digit = char.hexDigitValue else { return 0 }
      result = result * 16 + Decimal(digit)
    }

    let divisor = pow(Decimal(10), decimals)
    return result / divisor
  }

  private func formatAmount(_ amount: Decimal, symbol: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 6
    formatter.minimumFractionDigits = 2

    let formatted = formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    return symbol.isEmpty ? formatted : "\(formatted)"
  }

  private func pow(_ base: Decimal, _ exponent: Int) -> Decimal {
    guard exponent > 0 else { return 1 }
    var result = base
    for _ in 1..<exponent {
      result *= base
    }
    return result
  }

  private static let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let iso8601NoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  private func parseDate(_ string: String?) -> Date {
    guard let string else { return Date.distantPast }
    return Self.iso8601.date(from: string)
      ?? Self.iso8601NoFrac.date(from: string)
      ?? Date.distantPast
  }

  // MARK: - Date grouping

  private func groupByDate(_ records: [TransactionRecord]) -> [TransactionDateSection] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: records) { record in
      calendar.startOfDay(for: record.blockSignedAt)
    }

    let titleFormatter = DateFormatter()
    titleFormatter.dateFormat = "EEE, dd MMM"

    let idFormatter = DateFormatter()
    idFormatter.dateFormat = "yyyy-MM-dd"

    return grouped.map { (date, txs) in
      TransactionDateSection(
        id: idFormatter.string(from: date),
        title: titleFormatter.string(from: date),
        transactions: txs
      )
    }
    .sorted { lhs, rhs in
      guard let lDate = lhs.transactions.first?.blockSignedAt,
        let rDate = rhs.transactions.first?.blockSignedAt
      else {
        return false
      }
      return lDate > rDate
    }
  }
}
