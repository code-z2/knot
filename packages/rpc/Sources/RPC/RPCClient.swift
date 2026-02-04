import Foundation
import BigInt
import web3swift

public actor RPCClient {
  private let endpointsByChain: [UInt64: ChainEndpoints]
  private var requestID: Int = 1

  public init(endpointsByChain: [UInt64: ChainEndpoints]? = nil) {
    self.endpointsByChain = endpointsByChain ?? rpcDefaultEndpoints
  }

  public func getRpcUrl(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.rpcURL
  }

  public func getBundlerUrl(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.bundlerURL
  }

  public func getPaymasterUrl(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.paymasterURL
  }

  public func getSupportedChains() -> [UInt64] {
    Array(endpointsByChain.keys).sorted()
  }

  public func getWeb3Client(chainId: UInt64) async throws -> Web3 {
    let rpc = try getRpcUrl(chainId: chainId)
    guard let url = URL(string: rpc) else {
      throw RPCError.invalidURL(rpc)
    }
    return try await Web3.new(url, network: .Custom(networkID: BigUInt(chainId)))
  }

  public func makeRpcCall<Response: Decodable>(
    chainId: UInt64,
    method: String,
    params: [AnyCodable] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let rpc = try getRpcUrl(chainId: chainId)
    guard let url = URL(string: rpc) else {
      throw RPCError.invalidURL(rpc)
    }

    let id = requestID
    requestID += 1

    let payload = JSONRPCRequest(id: id, method: method, params: params)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, _) = try await URLSession.shared.data(for: request)
    let decoded = try JSONDecoder().decode(JSONRPCResponse<Response>.self, from: data)

    if let error = decoded.error {
      throw RPCError.rpcError(code: error.code, message: error.message)
    }

    guard let result = decoded.result else {
      throw RPCError.missingResult
    }
    return result
  }
}
