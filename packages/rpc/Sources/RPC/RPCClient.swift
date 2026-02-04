import Foundation
import BigInt
import web3swift

public actor RPCClient {
  private let endpointsByChain: [UInt64: ChainEndpoints]
  private var requestID: Int = 1

  public init(
    endpointsByChain: [UInt64: ChainEndpoints]? = nil,
    gelatoAPIKey: String? = nil,
    pimlicoAPIKey: String? = nil
  ) {
    if let endpointsByChain {
      self.endpointsByChain = endpointsByChain
      return
    }

    let resolvedGelato = gelatoAPIKey ?? Self.resolveSecret(
      envKey: RPCSecrets.gelatoKeyEnv,
      infoPlistKey: RPCSecrets.gelatoKeyInfoPlistKey
    )
    let resolvedPimlico = pimlicoAPIKey ?? Self.resolveSecret(
      envKey: RPCSecrets.pimlicoKeyEnv,
      infoPlistKey: RPCSecrets.pimlicoKeyInfoPlistKey
    )
    self.endpointsByChain = makeRPCDefaultEndpoints(
      gelatoAPIKey: resolvedGelato,
      pimlicoAPIKey: resolvedPimlico
    )
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
    return try await makeJSONRPCCall(
      urlString: rpc,
      method: method,
      params: params,
      responseType: responseType
    )
  }

  public func makeBundlerRpcCall<Response: Decodable>(
    chainId: UInt64,
    method: String,
    params: [AnyCodable] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let bundler = try getBundlerUrl(chainId: chainId)
    return try await makeJSONRPCCall(
      urlString: bundler,
      method: method,
      params: params,
      responseType: responseType
    )
  }

  public func makePaymasterRpcCall<Response: Decodable>(
    chainId: UInt64,
    method: String,
    params: [AnyCodable] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let paymaster = try getPaymasterUrl(chainId: chainId)
    return try await makeJSONRPCCall(
      urlString: paymaster,
      method: method,
      params: params,
      responseType: responseType
    )
  }

  public func getCode(chainId: UInt64, address: String, block: String = "latest") async throws -> String {
    try await makeRpcCall(
      chainId: chainId,
      method: "eth_getCode",
      params: [AnyCodable(address), AnyCodable(block)],
      responseType: String.self
    )
  }

  private func makeJSONRPCCall<Response: Decodable>(
    urlString: String,
    method: String,
    params: [AnyCodable] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    guard let url = URL(string: urlString), !urlString.isEmpty else {
      throw RPCError.invalidURL(urlString)
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

  private static func resolveSecret(envKey: String, infoPlistKey: String) -> String {
    let env = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !env.isEmpty { return env }

    if let plist = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String {
      let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    return ""
  }
}
