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

  /// Fetch a page of transactions for the given wallet (and optional accumulator) across chains.
  ///
  /// - Parameters:
  ///   - walletAddress: The user's EOA address.
  ///   - accumulatorAddress: The user's Accumulator address (same on all chains). Nil if unresolved.
  ///   - chainIds: Supported chain IDs to query.
  ///   - bearerToken: GoldRush API key.
  ///   - cursor: Pagination cursor for next page. Nil for first page.
  ///   - limit: Max items per page.
  /// - Returns: A page of classified, date-grouped transaction sections.
  public func fetchTransactions(
    walletAddress: String,
    accumulatorAddress: String?,
    chainIds: [UInt64],
    bearerToken: String,
    cursor: String? = nil,
    limit: Int = 50
  ) async throws -> TransactionPage {
    // Build URL
    let baseURL = RPCSecrets.allchainsTransactionsURLBase
    guard var components = URLComponents(string: baseURL) else {
      throw TransactionProviderError.invalidURL(baseURL)
    }

    var addresses = walletAddress
    if let acc = accumulatorAddress, !acc.isEmpty {
      addresses += ",\(acc)"
    }

    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "addresses", value: addresses),
      URLQueryItem(name: "chains", value: chainIds.map(String.init).joined(separator: ",")),
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "quote-currency", value: "USD"),
    ]
    if let cursor, !cursor.isEmpty {
      queryItems.append(URLQueryItem(name: "after", value: cursor))
    }
    components.queryItems = queryItems

    guard let url = components.url else {
      throw TransactionProviderError.invalidURL(baseURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      throw TransactionProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: GoldRushTxEnvelope
    do {
      envelope = try JSONDecoder().decode(GoldRushTxEnvelope.self, from: data)
    } catch {
      throw TransactionProviderError.decodingFailed
    }

    if let errorMessage = envelope.errorMessage, envelope.error == true {
      throw TransactionProviderError.apiError(message: errorMessage)
    }

    let items = envelope.data?.items ?? []
    let userAddr = walletAddress.lowercased()
    let accAddr = accumulatorAddress?.lowercased()

    // Classify and filter
    var records: [TransactionRecord] = []

    for item in items {
      // Detect cross-chain suppression via raw_log_topics
      if hasCrossChainInitiatedEvent(item) {
        continue // suppress source-chain scatter txs
      }

      let record = classify(item: item, userAddress: userAddr, accumulatorAddress: accAddr)
      records.append(record)
    }

    // Group by date
    let sections = groupByDate(records)

    return TransactionPage(
      sections: sections,
      cursorAfter: envelope.data?.cursorAfter,
      hasMore: envelope.data?.hasMore ?? false
    )
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

    // Find the primary Transfer event for value extraction
    let transfer = findPrimaryTransfer(item: item, userAddress: userAddress)

    let tokenSymbol = transfer?.symbol ?? (valueQuote > 0 ? "ETH" : "")
    let amountText = transfer?.amountText ?? ""
    let transferUSD = transfer?.usdValue ?? valueQuote

    // Classify variant
    let variant: TxRecordVariant
    if transfer != nil && transfer!.direction == .inbound {
      variant = .received
    } else if transfer != nil && transfer!.direction == .outbound {
      variant = .sent
    } else if to == userAddress && valueQuote > 0 {
      variant = .received
    } else if from == userAddress && (valueQuote > 0 || transfer != nil) {
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
  private func findPrimaryTransfer(item: GoldRushTxItem, userAddress: String) -> TransferInfo? {
    guard let logs = item.logEvents else { return nil }

    for log in logs {
      guard let topics = log.rawLogTopics,
            let topic0 = topics.first,
            topic0.lowercased() == Self.transferTopic0.lowercased(),
            topics.count >= 3 else { continue }

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

      if toTopic == userAddress {
        return TransferInfo(direction: .inbound, symbol: symbol, amountText: amountText, usdValue: usdValue)
      } else if fromTopic == userAddress {
        return TransferInfo(direction: .outbound, symbol: symbol, amountText: amountText, usdValue: usdValue)
      }
    }

    return nil
  }

  // MARK: - Multichain value extraction

  private func extractSourceChainAssets(_ item: GoldRushTxItem) -> [String] {
    // Attempt to decode sourceChains from the MultiChainIntentExecuted raw_log_data.
    // For now, return an empty array — full ABI decoding of uint256[] from raw data
    // is complex and can be added when accumulator transactions exist on-chain.
    // The UI will fall back to not showing the multi-chain icon group.
    return []
  }

  private func extractMultichainRecipient(_ item: GoldRushTxItem) -> String? {
    // The recipient is the 3rd indexed param (topic index 3) or in the data.
    // MultiChainIntentExecuted(bytes32 indexed intentId, address indexed user, address recipient, ...)
    // topic0 = sig, topic1 = intentId, topic2 = user
    // recipient is in log data (non-indexed)
    guard let logs = item.logEvents else { return nil }
    for log in logs {
      guard let topics = log.rawLogTopics,
            let topic0 = topics.first,
            topic0.lowercased() == Self.multiChainIntentExecutedTopic0.lowercased(),
            let rawData = log.rawLogData, rawData.count >= 66 else { continue }
      // First 32 bytes of data = recipient address (padded)
      return extractAddress(from: String(rawData.prefix(66)))
    }
    return nil
  }

  private func extractMultichainValue(_ item: GoldRushTxItem) -> (symbol: String?, amountText: String?, usdValue: Decimal?) {
    // Use GoldRush's tx-level value_quote as approximation
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

    // Parse hex to Decimal — handle large numbers
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
            let rDate = rhs.transactions.first?.blockSignedAt else {
        return false
      }
      return lDate > rDate
    }
  }
}
