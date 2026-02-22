import Foundation

public enum RPCError: Error {
    case unsupportedChain(UInt64)

    case invalidURL(String)

    case rpcError(code: Int, message: String)

    case missingResult

    case missingRelayProxyToken

    case invalidRelayProxyBaseURL(String)

    case relayRequestEncodingFailed(Error)

    case relayResponseDecodingFailed(Error)

    case relayServerError(status: Int, message: String)

    case relayPaymentRequired(RelayPaymentRequiredModel)
}

extension RPCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedChain(chainId):
            "No endpoints configured for chainId \(chainId)."

        case let .invalidURL(value):
            "Invalid URL configured: \(value)."

        case let .rpcError(code, message):
            "RPC error (\(code)): \(message)"

        case .missingResult:
            "RPC response did not contain a result."

        case .missingRelayProxyToken:
            "Relay proxy token is not configured."

        case let .invalidRelayProxyBaseURL(value):
            "Invalid relay proxy base URL: \(value)"

        case let .relayRequestEncodingFailed(error):
            "Relay proxy request encoding failed: \(error.localizedDescription)"

        case let .relayResponseDecodingFailed(error):
            "Relay proxy response decoding failed: \(error.localizedDescription)"

        case let .relayServerError(status, message):
            "Relay proxy error (\(status)): \(message)"

        case let .relayPaymentRequired(payload):
            "Gas tank top-up required. Need at least \(payload.requiredTopUpUsdc) USDC (suggested \(payload.suggestedTopUpUsdc) USDC)."
        }
    }
}
