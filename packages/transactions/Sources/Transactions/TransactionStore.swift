import Foundation
import RPC

/// Serializable cache payload for `TransactionStore`.
public struct TransactionStoreSnapshot: Codable, Sendable {
  public let sections: [TransactionDateSection]
  public let hasMore: Bool
  public let lastRefreshed: Date?

  public init(sections: [TransactionDateSection], hasMore: Bool, lastRefreshed: Date?) {
    self.sections = sections
    self.hasMore = hasMore
    self.lastRefreshed = lastRefreshed
  }
}

/// Observable store for multichain transaction history.
///
/// Create once at the app root and pass down to views that need transaction data.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class TransactionStore {
  public private(set) var sections: [TransactionDateSection] = []
  public private(set) var isLoading: Bool = false
  public private(set) var hasMore: Bool = false
  public private(set) var lastRefreshed: Date?
  public private(set) var error: Error?

  private var currentCursor: String?
  private var lastWalletAddress: String?
  private var cachedAccumulatorAddress: String?
  private var isLoadingNextPage: Bool = false

  /// Minimum interval between pull-to-refresh calls (seconds).
  private let silentRefreshCooldown: TimeInterval = 15
  private var lastSilentRefreshTriggered: Date?

  private let provider: ZerionTransactionProvider
  private let rpcClient: RPCClient
  private let accumulatorConfig: AccumulatorConfig
  private let chainResolver: ZerionChainResolver

  public init(
    provider: ZerionTransactionProvider = .init(),
    rpcClient: RPCClient = .init(),
    accumulatorConfig: AccumulatorConfig = .default,
    chainResolver: ZerionChainResolver = .shared
  ) {
    self.provider = provider
    self.rpcClient = rpcClient
    self.accumulatorConfig = accumulatorConfig
    self.chainResolver = chainResolver
  }

  /// Full refresh — clears existing data, fetches page 1.
  public func refresh(walletAddress: String) async {
    guard !walletAddress.isEmpty else {
      return
    }

    lastWalletAddress = walletAddress
    isLoading = true
    error = nil
    currentCursor = nil
    defer { isLoading = false }

    await performFetch(walletAddress: walletAddress, cursor: nil, replace: true)
  }

  /// Silent refresh triggered by pull-to-refresh. Does not set `isLoading`
  /// (no skeleton) and enforces a cooldown to debounce rapid pulls.
  @discardableResult
  public func silentRefresh() async -> Bool {
    guard let wallet = lastWalletAddress, !wallet.isEmpty else { return false }

    if let last = lastSilentRefreshTriggered,
      Date().timeIntervalSince(last) < silentRefreshCooldown
    {
      return false
    }

    lastSilentRefreshTriggered = Date()
    currentCursor = nil
    await performFetch(walletAddress: wallet, cursor: nil, replace: true)
    return true
  }

  /// Load next page (append to existing sections).
  public func loadNextPage() async {
    guard hasMore, !isLoadingNextPage else { return }
    guard let wallet = lastWalletAddress, !wallet.isEmpty else { return }
    guard let cursor = currentCursor else { return }

    isLoadingNextPage = true
    defer { isLoadingNextPage = false }

    await performFetch(walletAddress: wallet, cursor: cursor, replace: false)
  }

  // MARK: - Private

  private func performFetch(walletAddress: String, cursor: String?, replace: Bool) async {
    do {
      let chains = await rpcClient.getSupportedChains()
      guard let firstChain = chains.first else {
        return
      }

      let apiKey = try await rpcClient.getAddressActivityApiBearerToken(chainId: firstChain)
      let transactionsAPIURL = try await rpcClient.getAddressActivityApiUrl(chainId: firstChain)
      let mode = ChainSupportRuntime.resolveMode()
      let supportedChainIDs = Set(chains)
      let zerionChainMapping = try await chainResolver.resolve(
        apiBaseURL: transactionsAPIURL,
        apiKey: apiKey,
        mode: mode,
        supportedChainIDs: supportedChainIDs
      )
      let includeTestnets = chains.allSatisfy(Self.isKnownTestnetChain)

      // Resolve accumulator address (cached after first call)
      let accAddress = await resolveAccumulatorAddress(walletAddress: walletAddress)

      let page = try await provider.fetchTransactions(
        walletAddress: walletAddress,
        accumulatorAddress: accAddress,
        transactionsAPIURL: transactionsAPIURL,
        apiKey: apiKey,
        supportedChainIDs: supportedChainIDs,
        includeTestnets: includeTestnets,
        cursorAfter: cursor,
        zerionChainMapping: zerionChainMapping
      )

      if replace {
        sections = page.sections
      } else {
        mergeSections(page.sections)
      }

      currentCursor = page.cursorAfter
      hasMore = page.hasMore
      lastRefreshed = Date()
    } catch {
      self.error = error
    }
  }

  /// Resolve the user's accumulator address. Cached for the session.
  private func resolveAccumulatorAddress(walletAddress: String) async -> String? {
    if let cached = cachedAccumulatorAddress {
      return cached
    }

    guard !accumulatorConfig.factoryAddress.isEmpty,
      !accumulatorConfig.spokePoolByChain.isEmpty
    else {
      return nil
    }

    // TODO: Call AccumulatorFactory.computeAddress(userAccount)
    // via eth_call once deterministic deployment is done.
    _ = walletAddress
    return nil
  }

  /// Merge new sections into existing (handle date-boundary merging).
  private func mergeSections(_ newSections: [TransactionDateSection]) {
    guard !newSections.isEmpty else { return }

    if sections.isEmpty {
      sections = newSections
      return
    }

    if let lastExisting = sections.last,
      let firstNew = newSections.first,
      lastExisting.id == firstNew.id
    {
      var merged = sections
      let lastIndex = merged.count - 1
      merged[lastIndex] = TransactionDateSection(
        id: lastExisting.id,
        title: lastExisting.title,
        transactions: lastExisting.transactions + firstNew.transactions
      )
      merged.append(contentsOf: newSections.dropFirst())
      sections = merged
    } else {
      sections.append(contentsOf: newSections)
    }
  }

  public func snapshot() -> TransactionStoreSnapshot {
    TransactionStoreSnapshot(
      sections: sections,
      hasMore: hasMore,
      lastRefreshed: lastRefreshed
    )
  }

  public func restore(from snapshot: TransactionStoreSnapshot) {
    sections = snapshot.sections
    hasMore = snapshot.hasMore
    lastRefreshed = snapshot.lastRefreshed
    error = nil
  }

  private static func isKnownTestnetChain(_ chainID: UInt64) -> Bool {
    [11_155_111, 84_532, 421_614, 10_143, 20_143].contains(chainID)
  }
}
