import Foundation
import RPC

/// Serializable cache payload for `BalanceStore`.
public struct BalanceStoreSnapshot: Codable, Sendable {
    public let balances: [TokenBalance]
    public let activeChainIDs: [UInt64]
    public let totalValueUSD: Decimal
    public let lastRefreshed: Date?

    public init(
        balances: [TokenBalance],
        activeChainIDs: [UInt64],
        totalValueUSD: Decimal,
        lastRefreshed: Date?,
    ) {
        self.balances = balances
        self.activeChainIDs = activeChainIDs
        self.totalValueUSD = totalValueUSD
        self.lastRefreshed = lastRefreshed
    }
}

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

    private let provider: ZerionBalanceProvider
    private let rpcClient: RPCClient
    private let chainResolver: ZerionChainResolver

    public init(
        provider: ZerionBalanceProvider = .init(),
        rpcClient: RPCClient = .init(),
        chainResolver: ZerionChainResolver = .shared,
    ) {
        self.provider = provider
        self.rpcClient = rpcClient
        self.chainResolver = chainResolver
    }

    /// Refresh balances for the given wallet across all supported chains.
    public func refresh(walletAddress: String) async {
        guard !walletAddress.isEmpty else {
            return
        }

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

        if let last = lastSilentRefreshTriggered,
           Date().timeIntervalSince(last) < silentRefreshCooldown
        {
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
            guard let firstChain = chains.first else {
                return
            }

            let positionsAPIURL = try await rpcClient.getWalletApiUrl(chainId: firstChain)
            let apiKey = try await rpcClient.getWalletApiBearerToken(chainId: firstChain)
            let mode = ChainSupportRuntime.resolveMode()
            let chainSet = Set(chains)
            let zerionChainMapping = try await chainResolver.resolve(
                apiBaseURL: positionsAPIURL,
                apiKey: apiKey,
                mode: mode,
                supportedChainIDs: chainSet,
            )

            let includeTestnets = chains.allSatisfy(ChainRegistry.isTestnet(chainID:))

            balances = try await provider.fetchBalances(
                walletAddress: walletAddress,
                positionsAPIURL: positionsAPIURL,
                apiKey: apiKey,
                supportedChainIDs: chainSet,
                includeTestnets: includeTestnets,
                zerionChainMapping: zerionChainMapping,
            )

            let derivedActiveChainIDs = Set(
                balances.flatMap { $0.chainBalances.map(\.chainID) },
            )
            activeChainIDs = derivedActiveChainIDs.sorted()
            totalValueUSD = balances.reduce(Decimal.zero) { $0 + $1.totalValueUSD }
            lastRefreshed = Date()
        } catch {
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

    public func snapshot() -> BalanceStoreSnapshot {
        BalanceStoreSnapshot(
            balances: balances,
            activeChainIDs: activeChainIDs,
            totalValueUSD: totalValueUSD,
            lastRefreshed: lastRefreshed,
        )
    }

    public func restore(from snapshot: BalanceStoreSnapshot) {
        balances = snapshot.balances
        activeChainIDs = snapshot.activeChainIDs
        totalValueUSD = snapshot.totalValueUSD
        lastRefreshed = snapshot.lastRefreshed
        error = nil
    }
}
