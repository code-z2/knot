import Foundation

/// Canonical multichain token balance model.
///
/// Tokens are grouped by ``symbol`` (case-insensitive) across chains.
/// Spam tokens are excluded before grouping.
public struct TokenBalance: Identifiable, Hashable, Sendable {
  /// Stable ID: lowercased `symbol`.
  public let id: String
  public let symbol: String
  public let name: String
  public let contractAddress: String
  public let decimals: Int
  public let isNative: Bool

  /// Aggregated across all chains the user holds this token on.
  public let totalBalance: Decimal
  public let totalValueUSD: Decimal

  /// Per-unit price in USD (from the first chain that reports a rate).
  public let quoteRate: Decimal
  public let quoteRate24h: Decimal?

  /// Remote logo URL from GoldRush.
  public let logoURL: URL?

  /// Breakdown by chain.
  public let chainBalances: [ChainBalance]

  public init(
    id: String,
    symbol: String,
    name: String,
    contractAddress: String,
    decimals: Int,
    isNative: Bool,
    totalBalance: Decimal,
    totalValueUSD: Decimal,
    quoteRate: Decimal,
    quoteRate24h: Decimal?,
    logoURL: URL?,
    chainBalances: [ChainBalance]
  ) {
    self.id = id
    self.symbol = symbol
    self.name = name
    self.contractAddress = contractAddress
    self.decimals = decimals
    self.isNative = isNative
    self.totalBalance = totalBalance
    self.totalValueUSD = totalValueUSD
    self.quoteRate = quoteRate
    self.quoteRate24h = quoteRate24h
    self.logoURL = logoURL
    self.chainBalances = chainBalances
  }
}

public struct ChainBalance: Hashable, Sendable {
  public let chainID: UInt64
  public let chainName: String
  public let balance: Decimal
  public let valueUSD: Decimal
  public let contractAddress: String

  public init(
    chainID: UInt64,
    chainName: String,
    balance: Decimal,
    valueUSD: Decimal,
    contractAddress: String
  ) {
    self.chainID = chainID
    self.chainName = chainName
    self.balance = balance
    self.valueUSD = valueUSD
    self.contractAddress = contractAddress
  }
}

// MARK: - Convenience

extension TokenBalance {
  /// 24-hour price change as a fraction (e.g., 0.0324 means +3.24%).
  /// Returns nil if `quoteRate24h` is unavailable or zero.
  public var priceChangeRatio24h: Decimal? {
    guard let rate24h = quoteRate24h, rate24h > 0 else { return nil }
    return (quoteRate - rate24h) / rate24h
  }

  /// Formatted human-readable balance (e.g., "36.42").
  public var formattedBalance: String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = max(2, min(decimals, 8))
    formatter.groupingSeparator = ""
    return formatter.string(from: totalBalance as NSDecimalNumber) ?? "0"
  }
}
