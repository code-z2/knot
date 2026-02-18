import Foundation

public struct ChainEndpoints: Sendable, Equatable {
    public let rpcURL: String
    public let walletAPIURL: String
    public let walletAPIBearerToken: String
    public let addressActivityAPIURL: String
    public let addressActivityAPIBearerToken: String

    public init(
        rpcURL: String,
        walletAPIURL: String = "",
        walletAPIBearerToken: String = "",
        addressActivityAPIURL: String = "",
        addressActivityAPIBearerToken: String = "",
    ) {
        self.rpcURL = rpcURL
        self.walletAPIURL = walletAPIURL
        self.walletAPIBearerToken = walletAPIBearerToken
        self.addressActivityAPIURL = addressActivityAPIURL
        self.addressActivityAPIBearerToken = addressActivityAPIBearerToken
    }
}

struct JSONRPCRequest: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: [AnyCodable]
}

struct JSONRPCResponse<ResultType: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: ResultType?
    let error: JSONRPCErrorPayload?
}

struct JSONRPCErrorPayload: Decodable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

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
    case relayPaymentRequired(RelayPaymentRequired)
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
