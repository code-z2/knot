import Foundation
import BigInt
import web3swift

public actor RPCClient {
  private let endpointsByChain: [UInt64: ChainEndpoints]
  private var requestID: Int = 1

  public init(
    endpointsByChain: [UInt64: ChainEndpoints]? = nil,
    jsonRPCAPIKey: String? = nil,
    bundlerAPIKey: String? = nil,
    paymasterAPIKey: String? = nil,
    walletAPIKey: String? = nil,
    transactionsAPIKey: String? = nil
  ) {
    if let endpointsByChain {
      self.endpointsByChain = endpointsByChain
      return
    }

    let resolvedJSONRPCAPIKey = jsonRPCAPIKey ?? Self.resolveSetting(
      infoPlistKey: RPCSecrets.jsonRPCKeyInfoPlistKey
    )
    let resolvedBundlerAPIKey = bundlerAPIKey ?? Self.resolveSetting(
      infoPlistKey: RPCSecrets.bundlerKeyInfoPlistKey
    )
    let resolvedPaymasterAPIKey = paymasterAPIKey ?? Self.resolveSetting(
      infoPlistKey: RPCSecrets.paymasterKeyInfoPlistKey
    )
    let resolvedWalletAPIKey = walletAPIKey ?? Self.resolveSetting(
      infoPlistKey: RPCSecrets.walletAPIKeyInfoPlistKey
    )
    let resolvedTransactionsAPIKey = transactionsAPIKey ?? Self.resolveSetting(
      infoPlistKey: RPCSecrets.transactionsAPIKeyInfoPlistKey
    )
    let endpointConfig = RPCEndpointBuilderConfig(
      jsonRPCAPIKey: resolvedJSONRPCAPIKey,
      bundlerAPIKey: resolvedBundlerAPIKey,
      paymasterAPIKey: resolvedPaymasterAPIKey,
      walletAPIKey: resolvedWalletAPIKey,
      transactionsAPIKey: resolvedTransactionsAPIKey,
      jsonRPCURLTemplate: RPCSecrets.jsonRPCURLTemplate,
      bundlerURLTemplate: RPCSecrets.bundlerURLTemplate,
      paymasterURLTemplate: RPCSecrets.paymasterURLTemplate,
      walletAPIURLTemplate: RPCSecrets.walletAPIURLTemplate,
      transactionsAPIURLTemplate: RPCSecrets.transactionsAPIURLTemplate
    )
    let defaultEndpoints = makeRPCDefaultEndpoints(
      config: endpointConfig
    )
    self.endpointsByChain = Self.applyChainSupportMode(defaultEndpoints)
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

  public func getWalletApiUrl(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.walletAPIURL
  }

  public func getWalletApiBearerToken(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.walletAPIBearerToken
  }

  public func getTransactionsApiUrl(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.transactionsAPIURL
  }

  public func getTransactionsApiBearerToken(chainId: UInt64) throws -> String {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints.transactionsAPIBearerToken
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

  private static func resolveSetting(
    infoPlistKey: String,
    defaultValue: String = ""
  ) -> String {
    if let plist = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String {
      let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
    }

    return defaultValue
  }

  private static func resolveChainSupportConfig() -> ChainSupportConfig? {
    let config = ChainSupportRuntime.resolveConfig()
    guard !config.chainIDs.isEmpty else { return nil }
    return config
  }

  private static func applyChainSupportMode(_ endpointsByChain: [UInt64: ChainEndpoints]) -> [UInt64: ChainEndpoints] {
    guard let config = resolveChainSupportConfig() else {
      return endpointsByChain
    }

    let allowed = Set(config.chainIDs)
    return endpointsByChain.filter { allowed.contains($0.key) }
  }
}
