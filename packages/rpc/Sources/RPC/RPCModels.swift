import Foundation

public struct ChainEndpoints: Sendable, Equatable {
  public let rpcURL: String
  public let bundlerURL: String
  public let paymasterURL: String

  public init(rpcURL: String, bundlerURL: String, paymasterURL: String) {
    self.rpcURL = rpcURL
    self.bundlerURL = bundlerURL
    self.paymasterURL = paymasterURL
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
