import Foundation

/// Errors from route resolution.
public enum RouteError: Error, Sendable {
    case noRouteFound(reason: String)

    case quoteUnavailable(provider: String, reason: String)

    case insufficientBalance

    case unsupportedChain(UInt64)

    case unsupportedAsset(String)
}
