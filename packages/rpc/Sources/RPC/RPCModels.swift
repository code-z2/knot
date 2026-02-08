import Foundation

public struct ChainEndpoints: Sendable, Equatable {
  public let rpcURL: String
  public let bundlerURL: String
  public let paymasterURL: String
  public let walletAPIURL: String
  public let walletAPIBearerToken: String
  public let addressActivityAPIURL: String
  public let addressActivityAPIBearerToken: String

  public init(
    rpcURL: String,
    bundlerURL: String,
    paymasterURL: String,
    walletAPIURL: String = "",
    walletAPIBearerToken: String = "",
    addressActivityAPIURL: String = "",
    addressActivityAPIBearerToken: String = ""
  ) {
    self.rpcURL = rpcURL
    self.bundlerURL = bundlerURL
    self.paymasterURL = paymasterURL
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
    }
  }
}
