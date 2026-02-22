import Foundation

public enum ZerionChainResolverError: Error {
    case invalidURL(String)

    case httpError(statusCode: Int)

    case noSupportedChainsResolved(mode: ChainSupportMode, supportedChainIDs: [UInt64])

    case invalidResponse
}
