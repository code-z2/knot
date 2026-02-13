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

/// Fetches multichain transaction history from Zerion wallet transactions endpoint.
public actor ZerionTransactionProvider {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func fetchTransactions(
    walletAddress: String,
    accumulatorAddress: String?,
    transactionsAPIURL: String,
    apiKey: String,
    supportedChainIDs: Set<UInt64>,
    includeTestnets: Bool,
    cursorAfter: String?,
    includeTrash: Bool = false
  ) async throws -> TransactionPage {
    let walletPage = try await fetchWalletPage(
      address: walletAddress,
      transactionsAPIURL: transactionsAPIURL,
      apiKey: apiKey,
      supportedChainIDs: supportedChainIDs,
      includeTestnets: includeTestnets,
      cursorAfter: cursorAfter,
      includeTrash: includeTrash
    )

    var allItems = walletPage.items

    if let accumulatorAddress, !accumulatorAddress.isEmpty {
      let accumulatorPage = try await fetchWalletPage(
        address: accumulatorAddress,
        transactionsAPIURL: transactionsAPIURL,
        apiKey: apiKey,
        supportedChainIDs: supportedChainIDs,
        includeTestnets: includeTestnets,
        cursorAfter: nil,
        includeTrash: includeTrash
      )
      allItems.append(contentsOf: accumulatorPage.items)
    }

    let userAddress = walletAddress.lowercased()
    let accumulator = accumulatorAddress?.lowercased()

    var seen = Set<String>()
    var records: [TransactionRecord] = []

    for item in allItems {
      let record = classify(
        item: item,
        userAddress: userAddress,
        accumulatorAddress: accumulator
      )

      guard !record.txHash.isEmpty else { continue }
      guard seen.insert(record.id).inserted else { continue }
      records.append(record)
    }

    records.sort { $0.blockSignedAt > $1.blockSignedAt }

    return TransactionPage(
      sections: groupByDate(records),
      cursorAfter: walletPage.cursorAfter,
      hasMore: walletPage.hasMore
    )
  }

  private struct WalletTransactionPage {
    let items: [ZerionTransactionItem]
    let cursorAfter: String?
    let hasMore: Bool
  }

  private func fetchWalletPage(
    address: String,
    transactionsAPIURL: String,
    apiKey: String,
    supportedChainIDs: Set<UInt64>,
    includeTestnets: Bool,
    cursorAfter: String?,
    includeTrash: Bool
  ) async throws -> WalletTransactionPage {
    let endpointURLString = transactionsAPIURL.replacingOccurrences(
      of: "{walletAddress}",
      with: address
    )

    guard var components = URLComponents(string: endpointURLString) else {
      throw TransactionProviderError.invalidURL(endpointURLString)
    }

    let zerionChainIDs = supportedChainIDs.compactMap { ChainRegistry.zerionChainID(chainID: $0) }

    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "currency", value: "usd"),
      URLQueryItem(name: "filter[trash]", value: includeTrash ? "no_filter" : "only_non_trash"),
      URLQueryItem(name: "page[size]", value: "100"),
    ]

    if !zerionChainIDs.isEmpty {
      queryItems.append(
        URLQueryItem(name: "filter[chain_ids]", value: zerionChainIDs.joined(separator: ","))
      )
    }

    if let cursorAfter, !cursorAfter.isEmpty {
      queryItems.append(URLQueryItem(name: "page[after]", value: cursorAfter))
    }

    components.queryItems = queryItems

    guard let url = components.url else {
      throw TransactionProviderError.invalidURL(endpointURLString)
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
        throw TransactionProviderError.apiError(message: String(body))
      }
      throw TransactionProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: ZerionTransactionsEnvelope
    do {
      envelope = try JSONDecoder().decode(ZerionTransactionsEnvelope.self, from: data)
    } catch {
      throw TransactionProviderError.decodingFailed
    }

    let nextCursor = parseCursorAfter(nextLink: envelope.links?.next)
    return WalletTransactionPage(
      items: envelope.data,
      cursorAfter: nextCursor,
      hasMore: nextCursor != nil
    )
  }

  private static func basicAuthValue(apiKey: String) -> String {
    let raw = "\(apiKey):"
    return "Basic \(Data(raw.utf8).base64EncodedString())"
  }

  private func parseCursorAfter(nextLink: String?) -> String? {
    guard let nextLink,
      let components = URLComponents(string: nextLink)
    else {
      return nil
    }

    return components.queryItems?.first(where: { $0.name == "page[after]" })?.value
  }

  private func classify(
    item: ZerionTransactionItem,
    userAddress: String,
    accumulatorAddress: String?
  ) -> TransactionRecord {
    let chainKey = item.relationships?.chain?.data?.id?.lowercased() ?? ""
    let chainID = ChainRegistry.chainID(zerionChainID: chainKey) ?? 0
    let chainDefinition = ChainRegistry.resolveOrFallback(chainID: chainID)

    let txHash = item.attributes.hash ?? ""
    let from = item.attributes.sentFrom?.lowercased() ?? ""
    let to = item.attributes.sentTo?.lowercased() ?? ""
    let status = (item.attributes.status ?? "").lowercased() == "confirmed"
      ? TxRecordStatus.success
      : TxRecordStatus.failed

    var ownedAddresses = Set<String>([userAddress])
    if let accumulatorAddress {
      ownedAddresses.insert(accumulatorAddress)
    }

    let operationType = (item.attributes.operationType ?? "").lowercased()

    let transfer = selectPrimaryTransfer(
      transfers: item.attributes.transfers ?? []
    )

    let tokenSymbol = transfer?.symbol
      ?? item.attributes.fee?.fungibleInfo?.symbol
      ?? chainDefinition.assetName.uppercased()
    let amountText = transfer?.amountText ?? ""
    let valueQuoteUSD = transfer?.valueUSD ?? 0

    let variant: TxRecordVariant
    if let accumulatorAddress,
      from == accumulatorAddress,
      !ownedAddresses.contains(to),
      ["send", "trade", "execute", "withdraw"].contains(operationType)
    {
      variant = .multichain
    } else if operationType == "receive" || (ownedAddresses.contains(to) && !ownedAddresses.contains(from)) {
      variant = .received
    } else if operationType == "send" || ownedAddresses.contains(from) {
      variant = .sent
    } else {
      variant = .contract
    }

    let feeUSD = computeFeeUSD(item.attributes.fee)

    let date = parseDate(item.attributes.minedAt)

    return TransactionRecord(
      id: "\(chainID):\(txHash)",
      status: status,
      variant: variant,
      chainId: chainID,
      chainName: chainDefinition.name,
      txHash: txHash,
      fromAddress: from,
      toAddress: to,
      blockSignedAt: date,
      valueQuoteUSD: valueQuoteUSD,
      assetAmountText: amountText,
      tokenSymbol: tokenSymbol,
      gasQuoteUSD: feeUSD,
      networkAssetName: chainDefinition.assetName,
      accumulatedFromNetworkAssetNames: [],
      multichainRecipient: variant == .multichain ? to : nil
    )
  }

  private struct PrimaryTransfer {
    let symbol: String
    let amountText: String
    let valueUSD: Decimal
  }

  private func selectPrimaryTransfer(
    transfers: [ZerionTransactionTransfer]
  ) -> PrimaryTransfer? {
    guard let transfer = transfers.first else {
      return nil
    }

    let quantity = transfer.quantity?.decimalValue ?? 0
    let valueUSD = transfer.value?.value ?? 0
    let symbol = transfer.fungibleInfo?.symbol?.uppercased() ?? ""

    if quantity <= 0 || symbol.isEmpty {
      return nil
    }

    return PrimaryTransfer(
      symbol: symbol,
      amountText: formatAmount(quantity, symbol: symbol),
      valueUSD: valueUSD
    )
  }

  private func computeFeeUSD(_ fee: ZerionTransactionFee?) -> Decimal {
    if let value = fee?.value?.value, value > 0 {
      return value
    }

    let quantity = fee?.quantity?.decimalValue ?? 0
    let price = fee?.price?.value ?? 0
    if quantity > 0 && price > 0 {
      return quantity * price
    }

    return 0
  }

  private func formatAmount(_ amount: Decimal, symbol: String) -> String {
    let truncatedAmount = truncate(amount, fractionDigits: 4)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 4
    formatter.minimumFractionDigits = 0

    let formatted = formatter.string(from: truncatedAmount as NSDecimalNumber) ?? "0"
    return "\(formatted) \(symbol)"
  }

  private func truncate(_ value: Decimal, fractionDigits: Int) -> Decimal {
    var source = value
    var result = Decimal()
    if source >= 0 {
      NSDecimalRound(&result, &source, fractionDigits, .down)
    } else {
      NSDecimalRound(&result, &source, fractionDigits, .up)
    }
    return result
  }

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let iso8601NoFractions: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private func parseDate(_ value: String?) -> Date {
    guard let value else { return Date.distantPast }
    return Self.iso8601.date(from: value)
      ?? Self.iso8601NoFractions.date(from: value)
      ?? Date.distantPast
  }

  private func groupByDate(_ records: [TransactionRecord]) -> [TransactionDateSection] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: records) { record in
      calendar.startOfDay(for: record.blockSignedAt)
    }

    let titleFormatter = DateFormatter()
    titleFormatter.dateFormat = "EEE, dd MMM"

    let idFormatter = DateFormatter()
    idFormatter.dateFormat = "yyyy-MM-dd"

    return grouped.map { date, txs in
      TransactionDateSection(
        id: idFormatter.string(from: date),
        title: titleFormatter.string(from: date),
        transactions: txs
      )
    }
    .sorted { lhs, rhs in
      guard let leftDate = lhs.transactions.first?.blockSignedAt,
        let rightDate = rhs.transactions.first?.blockSignedAt
      else {
        return false
      }
      return leftDate > rightDate
    }
  }
}
