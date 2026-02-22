import Foundation

/// The type of action a route step performs.
public enum RouteAction: Sendable {
    /// Direct ERC20 transfer or native ETH send.
    case transfer

    /// On-chain swap via LiFi.
    case swap

    /// Cross-chain bridge via Across.
    case bridge

    /// Cross-chain bridge into Accumulator (scatter-gather).
    case accumulate
}
