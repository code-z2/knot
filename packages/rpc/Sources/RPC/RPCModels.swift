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
    addressActivityAPIBearerToken: String = ""
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
    case .unsupportedChain(let chainId):
      return "No endpoints configured for chainId \(chainId)."
    case .invalidURL(let value):
      return "Invalid URL configured: \(value)."
    case .rpcError(let code, let message):
      return "RPC error (\(code)): \(message)"
    case .missingResult:
      return "RPC response did not contain a result."
    case .missingRelayProxyToken:
      return "Relay proxy token is not configured."
    case .invalidRelayProxyBaseURL(let value):
      return "Invalid relay proxy base URL: \(value)"
    case .relayRequestEncodingFailed(let error):
      return "Relay proxy request encoding failed: \(error.localizedDescription)"
    case .relayResponseDecodingFailed(let error):
      return "Relay proxy response decoding failed: \(error.localizedDescription)"
    case .relayServerError(let status, let message):
      return "Relay proxy error (\(status)): \(message)"
    case .relayPaymentRequired(let payload):
      return "Gas tank top-up required. Need at least \(payload.requiredTopUpUsdc) USDC (suggested \(payload.suggestedTopUpUsdc) USDC)."
    }
  }
}
