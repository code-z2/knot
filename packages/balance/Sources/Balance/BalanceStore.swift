import Foundation
import RPC

/// Observable store that holds the current wallet's multichain token balances.
///
/// Create once at the app root and pass down to views that need balance data.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class BalanceStore {
  public private(set) var balances: [TokenBalance] = []
  public private(set) var activeChainIDs: [UInt64] = []
  public private(set) var totalValueUSD: Decimal = 0
  public private(set) var isLoading: Bool = false
  public private(set) var lastRefreshed: Date?
  public private(set) var error: Error?

  /// The last wallet address used for refresh. Enables parameterless silent refresh.
  private var lastWalletAddress: String?

  /// Minimum interval between pull-to-refresh calls (seconds).
  private let silentRefreshCooldown: TimeInterval = 15
  private var lastSilentRefreshTriggered: Date?

  private let provider: GoldRushBalanceProvider
  private let activityProvider: GoldRushActivityProvider
  private let rpcClient: RPCClient

  public init(
    provider: GoldRushBalanceProvider = .init(),
    activityProvider: GoldRushActivityProvider = .init(),
    rpcClient: RPCClient = .init()
  ) {
    self.provider = provider
    self.activityProvider = activityProvider
    self.rpcClient = rpcClient
  }

  /// Refresh balances for the given wallet across all supported chains.
  public func refresh(walletAddress: String) async {
    guard !walletAddress.isEmpty else {
      print("[BalanceStore] ⚠️ refresh called with empty wallet address")
      return
    }
    print("[BalanceStore] refresh(walletAddress: \(walletAddress.prefix(10))…)")
    lastWalletAddress = walletAddress
    isLoading = true
    error = nil
    defer { isLoading = false }

    await performFetch(walletAddress: walletAddress)
  }

  /// Silent refresh triggered by pull-to-refresh. Does not set `isLoading`
  /// (so no skeleton appears) and enforces a cooldown to debounce rapid pulls.
  /// Returns `true` if a refresh was actually triggered.
  @discardableResult
  public func silentRefresh() async -> Bool {
    guard let wallet = lastWalletAddress, !wallet.isEmpty else { return false }

    // Debounce: skip if a silent refresh happened within the cooldown window.
    if let last = lastSilentRefreshTriggered,
       Date().timeIntervalSince(last) < silentRefreshCooldown {
      return false
    }

    lastSilentRefreshTriggered = Date()
    await performFetch(walletAddress: wallet)
    return true
  }

  /// Shared fetch logic used by both `refresh` and `silentRefresh`.
  private func performFetch(walletAddress: String) async {
    do {
      let chains = await rpcClient.getSupportedChains()
      print("[BalanceStore] supportedChains = \(chains)")
      guard let firstChain = chains.first else {
        print("[BalanceStore] ⚠️ no supported chains — aborting fetch")
        return
      }

      let walletAPIURL = try await rpcClient.getWalletApiUrl(chainId: firstChain)
      let apiKey = try await rpcClient.getWalletApiBearerToken(chainId: firstChain)
      let activityURL = try await rpcClient.getAddressActivityApiUrl(chainId: firstChain)
      let activityToken = try await rpcClient.getAddressActivityApiBearerToken(chainId: firstChain)
      print("[BalanceStore] apiKey = \(apiKey.prefix(8))…")
      print("[BalanceStore] walletAPIURL = \(walletAPIURL)")
      print("[BalanceStore] activityURL = \(activityURL)")

      // Fetch balances and activity in parallel.
      async let fetchedBalances = provider.fetchBalances(
        walletAddress: walletAddress,
        walletAPIURL: walletAPIURL,
        bearerToken: apiKey
      )
      async let fetchedActivity = activityProvider.fetchActiveChainIDs(
        walletAddress: walletAddress,
        activityAPIURL: activityURL,
        bearerToken: activityToken,
        supportedChainIDs: Set(chains)
      )

      balances = try await fetchedBalances
      print("[BalanceStore] ✅ fetched \(balances.count) token groups")
      for b in balances {
        print("[BalanceStore]   • \(b.symbol): \(b.totalBalance) ($\(b.totalValueUSD)) across \(b.chainBalances.count) chain(s)")
      }

      do {
        activeChainIDs = try await fetchedActivity
        print("[BalanceStore] ✅ activeChainIDs = \(activeChainIDs)")
      } catch {
        print("[BalanceStore] ⚠️ activity fetch failed: \(error)")
        activeChainIDs = []
      }

      totalValueUSD = balances.reduce(Decimal.zero) { $0 + $1.totalValueUSD }
      lastRefreshed = Date()
      print("[BalanceStore] totalValueUSD = $\(totalValueUSD)")
    } catch {
      print("[BalanceStore] ❌ performFetch error: \(error)")
      self.error = error
    }
  }

  /// Lookup a single token's per-unit USD price by symbol.
  public func quoteRate(forSymbol symbol: String) -> Decimal? {
    balances.first { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }?.quoteRate
  }

  /// Lookup balance for a specific token by symbol.
  public func balance(forSymbol symbol: String) -> TokenBalance? {
    balances.first { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
  }
}
