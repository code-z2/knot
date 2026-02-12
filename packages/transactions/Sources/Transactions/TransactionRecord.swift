import Foundation

// MARK: - Domain Models

public enum TxRecordStatus: Hashable, Sendable, Codable {
  case success
  case failed
}

public enum TxRecordVariant: Hashable, Sendable, Codable {
  case received
  case sent
  case contract
  case multichain
}

/// Canonical transaction record replacing MockTransaction.
/// Built from wallet activity API data and classified by the provider.
public struct TransactionRecord: Identifiable, Hashable, Sendable, Codable {
  /// Unique ID: "chainId:txHash" for single-chain, "mc:txHash" for multichain
  public let id: String
  public let status: TxRecordStatus
  public let variant: TxRecordVariant
  public let chainId: UInt64
  public let chainName: String
  public let txHash: String
  public let fromAddress: String
  public let toAddress: String
  public let blockSignedAt: Date
  /// USD value of the primary asset change.
  public let valueQuoteUSD: Decimal
  /// Human-readable asset amount (e.g., "299.90 USDC").
  public let assetAmountText: String
  /// Primary token symbol involved (e.g., "USDC", "ETH").
  public let tokenSymbol: String
  /// Gas fee in USD.
  public let gasQuoteUSD: Decimal
  /// Chain asset name for icon lookup (maps to ChainRegistry.assetName).
  public let networkAssetName: String
  /// For multichain: the source chain asset names the funds were gathered from.
  public let accumulatedFromNetworkAssetNames: [String]
  /// For multichain: the recipient address.
  public let multichainRecipient: String?

  public init(
    id: String,
    status: TxRecordStatus,
    variant: TxRecordVariant,
    chainId: UInt64,
    chainName: String,
    txHash: String,
    fromAddress: String,
    toAddress: String,
    blockSignedAt: Date,
    valueQuoteUSD: Decimal,
    assetAmountText: String,
    tokenSymbol: String,
    gasQuoteUSD: Decimal,
    networkAssetName: String,
    accumulatedFromNetworkAssetNames: [String] = [],
    multichainRecipient: String? = nil
  ) {
    self.id = id
    self.status = status
    self.variant = variant
    self.chainId = chainId
    self.chainName = chainName
    self.txHash = txHash
    self.fromAddress = fromAddress
    self.toAddress = toAddress
    self.blockSignedAt = blockSignedAt
    self.valueQuoteUSD = valueQuoteUSD
    self.assetAmountText = assetAmountText
    self.tokenSymbol = tokenSymbol
    self.gasQuoteUSD = gasQuoteUSD
    self.networkAssetName = networkAssetName
    self.accumulatedFromNetworkAssetNames = accumulatedFromNetworkAssetNames
    self.multichainRecipient = multichainRecipient
  }
}

// MARK: - Section

/// A group of transactions sharing the same calendar day.
public struct TransactionDateSection: Identifiable, Hashable, Sendable, Codable {
  public let id: String
  public let title: String
  public let transactions: [TransactionRecord]

  public init(id: String, title: String, transactions: [TransactionRecord]) {
    self.id = id
    self.title = title
    self.transactions = transactions
  }
}

// MARK: - Page

/// Result of a single fetch from the provider.
public struct TransactionPage: Sendable, Codable {
  public let sections: [TransactionDateSection]
  public let cursorAfter: String?
  public let hasMore: Bool

  public init(sections: [TransactionDateSection], cursorAfter: String?, hasMore: Bool) {
    self.sections = sections
    self.cursorAfter = cursorAfter
    self.hasMore = hasMore
  }
}
