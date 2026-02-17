import BigInt
import CryptoKit
import Foundation
import web3swift

public actor RPCClient {
  private let baseEndpointResolver: any RPCEndpointResolving
  private let baseRelayConfig: RelayProxyConfig
  private let dynamicEnvironmentBundle: Bundle?
  private let transport: any JSONRPCTransporting
  private var requestID: Int = 1

  public init(
    environment: RPCEnvironment,
    transport: any JSONRPCTransporting = URLSessionJSONRPCTransport()
  ) {
    self.baseEndpointResolver = environment.makeResolver()
    self.baseRelayConfig = environment.relayConfig
    self.dynamicEnvironmentBundle = nil
    self.transport = transport
  }

  public init(
    resolver: any RPCEndpointResolving,
    relayConfig: RelayProxyConfig = .init(),
    transport: any JSONRPCTransporting = URLSessionJSONRPCTransport()
  ) {
    self.baseEndpointResolver = resolver
    self.baseRelayConfig = relayConfig
    self.dynamicEnvironmentBundle = nil
    self.transport = transport
  }

  public init(
    bundle: Bundle = .main,
    transport: any JSONRPCTransporting = URLSessionJSONRPCTransport()
  ) {
    let environment = Self.makeEnvironment(bundle: bundle)
    self.baseEndpointResolver = environment.makeResolver()
    self.baseRelayConfig = environment.relayConfig
    self.dynamicEnvironmentBundle = bundle
    self.transport = transport
  }

  public func getRpcUrl(chainId: UInt64) throws -> String {
    let endpoints = try runtimeEndpointResolver().endpoints(for: chainId)
    return endpoints.rpcURL
  }

  public func getWalletApiUrl(chainId: UInt64) throws -> String {
    let endpoints = try runtimeEndpointResolver().endpoints(for: chainId)
    return endpoints.walletAPIURL
  }

  public func getWalletApiBearerToken(chainId: UInt64) throws -> String {
    let endpoints = try runtimeEndpointResolver().endpoints(for: chainId)
    return endpoints.walletAPIBearerToken
  }

  public func getAddressActivityApiUrl(chainId: UInt64) throws -> String {
    let endpoints = try runtimeEndpointResolver().endpoints(for: chainId)
    return endpoints.addressActivityAPIURL
  }

  public func getAddressActivityApiBearerToken(chainId: UInt64) throws -> String {
    let endpoints = try runtimeEndpointResolver().endpoints(for: chainId)
    return endpoints.addressActivityAPIBearerToken
  }

  public func getSupportedChains() -> [UInt64] {
    runtimeEndpointResolver().supportedChains()
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

  public func getCode(chainId: UInt64, address: String, block: String = "latest") async throws
    -> String
  {
    try await makeRpcCall(
      chainId: chainId,
      method: "eth_getCode",
      params: [AnyCodable(address), AnyCodable(block)],
      responseType: String.self
    )
  }

  public func relaySubmit(
    account: String,
    supportMode: RelaySupportMode,
    priorityTxs: [RelayTx],
    txs: [RelayTx],
    paymentOptions: [RelayPaymentOption] = []
  ) async throws -> RelaySubmitResult {
    let payload = RelaySubmitRequest(
      account: account,
      supportMode: supportMode.rawValue,
      priorityTxs: priorityTxs.map(RelaySubmitTxPayload.init),
      txs: txs.map(RelaySubmitTxPayload.init),
      paymentOptions: paymentOptions
    )

    return try await relayCall(
      path: "/v1/relay/submit",
      method: "POST",
      body: payload,
      responseType: RelaySubmitResult.self
    )
  }

  public func relayStatus(chainId: UInt64, id: String) async throws -> RelayStatus {
    let response: RelayStatusResponse = try await relayCall(
      path: "/v1/relay/status",
      method: "GET",
      queryItems: [
        URLQueryItem(name: "chainId", value: String(chainId)),
        URLQueryItem(name: "id", value: id),
      ],
      responseType: RelayStatusResponse.self
    )
    return response.status
  }

  public func relayCredit(
    account: String,
    supportMode: RelaySupportMode
  ) async throws -> RelayCreditResult {
    try await relayCall(
      path: "/v1/relay/credit",
      method: "GET",
      queryItems: [
        URLQueryItem(name: "account", value: account),
        URLQueryItem(name: "supportMode", value: supportMode.rawValue),
      ],
      responseType: RelayCreditResult.self
    )
  }

  public func relayFaucetFund(
    eoaAddress: String,
    supportMode: RelaySupportMode
  ) async throws -> RelayFaucetFundResult {
    let payload = RelayFaucetFundRequestPayload(
      eoaAddress: eoaAddress,
      supportMode: supportMode.rawValue
    )
    return try await relayCall(
      path: "/v1/faucet/fund",
      method: "POST",
      body: payload,
      responseType: RelayFaucetFundResult.self
    )
  }

  public func relayCreateImageUploadSession(
    eoaAddress: String,
    fileName: String,
    contentType: String
  ) async throws -> RelayImageUploadSession {
    let payload = RelayImageUploadSessionRequestPayload(
      eoaAddress: eoaAddress,
      fileName: fileName,
      contentType: contentType
    )

    let bodyData: Data
    do {
      bodyData = try JSONEncoder().encode(payload)
    } catch {
      throw RPCError.relayRequestEncodingFailed(error)
    }

    return try await relayCall(
      path: "/v1/images/direct-upload",
      method: "POST",
      queryItems: [],
      bodyData: bodyData,
      responseType: RelayImageUploadSession.self,
      endpointBaseURL: try uploadProxyBaseURL()
    )
  }

  public func relayCall<Response: Decodable, Body: Encodable>(
    path: String,
    method: String,
    queryItems: [URLQueryItem] = [],
    body: Body,
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let bodyData: Data
    do {
      bodyData = try JSONEncoder().encode(body)
    } catch {
      throw RPCError.relayRequestEncodingFailed(error)
    }

    return try await relayCall(
      path: path,
      method: method,
      queryItems: queryItems,
      bodyData: bodyData,
      responseType: responseType
    )
  }

  public func relayCall<Response: Decodable>(
    path: String,
    method: String,
    queryItems: [URLQueryItem] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await relayCall(
      path: path,
      method: method,
      queryItems: queryItems,
      bodyData: Data(),
      responseType: responseType
    )
  }

  private func makeJSONRPCCall<Response: Decodable>(
    urlString: String,
    method: String,
    params: [AnyCodable] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let id = requestID
    requestID += 1

    return try await transport.send(
      urlString: urlString,
      method: method,
      params: params,
      requestID: id,
      responseType: responseType
    )
  }

  private func relayCall<Response: Decodable>(
    path: String,
    method: String,
    queryItems: [URLQueryItem],
    bodyData: Data,
    responseType: Response.Type,
    endpointBaseURL: URL? = nil
  ) async throws -> Response {
    let token = try relayClientToken()
    let baseURL = try (endpointBaseURL ?? relayBaseURL())
    let endpointBase = relayEndpoint(baseURL: baseURL, path: path)
    var components = URLComponents(
      url: endpointBase,
      resolvingAgainstBaseURL: false
    )
    if !queryItems.isEmpty {
      components?.queryItems = queryItems
    }
    guard let endpoint = components?.url else {
      throw RPCError.invalidRelayProxyBaseURL(baseURL.absoluteString + path)
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData.isEmpty ? nil : bodyData
    applyRelaySignatureHeaders(&request, bodyData: bodyData)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw RPCError.relayServerError(status: -1, message: "No HTTP response")
    }

    if httpResponse.statusCode == 402 {
      do {
        let paymentRequired = try JSONDecoder().decode(RelayPaymentRequired.self, from: data)
        throw RPCError.relayPaymentRequired(paymentRequired)
      } catch let error as RPCError {
        throw error
      } catch {
        throw RPCError.relayResponseDecodingFailed(error)
      }
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "Unknown relay proxy error"
      throw RPCError.relayServerError(status: httpResponse.statusCode, message: message)
    }

    do {
      return try JSONDecoder().decode(responseType, from: data)
    } catch {
      throw RPCError.relayResponseDecodingFailed(error)
    }
  }

  private func relayBaseURL() throws -> URL {
    let relayConfig = runtimeRelayConfig()
    let configured = relayConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = RPCSecrets.relayProxyBaseURLDefault
    let resolved = configured.isEmpty ? fallback : configured
    let urlString = resolved.contains("://") ? resolved : "https://\(resolved)"
    guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
      throw RPCError.invalidRelayProxyBaseURL(resolved)
    }
    return url
  }

  private func uploadProxyBaseURL() throws -> URL {
    let relayConfig = runtimeRelayConfig()
    let configured = relayConfig.uploadBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if configured.isEmpty {
      throw RPCError.invalidRelayProxyBaseURL("UPLOAD_PROXY_BASE_URL is not configured.")
    }

    let urlString = configured.contains("://") ? configured : "https://\(configured)"
    guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
      throw RPCError.invalidRelayProxyBaseURL(configured)
    }
    return url
  }

  private func relayEndpoint(baseURL: URL, path: String) -> URL {
    path
      .split(separator: "/")
      .reduce(baseURL) { partialResult, segment in
        partialResult.appendingPathComponent(String(segment), isDirectory: false)
      }
  }

  private func relayClientToken() throws -> String {
    let relayConfig = runtimeRelayConfig()
    let token = relayConfig.clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      throw RPCError.missingRelayProxyToken
    }
    return token
  }

  private func applyRelaySignatureHeaders(_ request: inout URLRequest, bodyData: Data) {
    let timestamp = String(Int(Date().timeIntervalSince1970))
    request.setValue(timestamp, forHTTPHeaderField: "X-Relay-Timestamp")

    let relayConfig = runtimeRelayConfig()
    let hmacSecret = relayConfig.hmacSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !hmacSecret.isEmpty else {
      return
    }

    let payload = "\(timestamp).\(String(data: bodyData, encoding: .utf8) ?? "")"
    let key = SymmetricKey(data: Data(hmacSecret.utf8))
    let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
    let signature = mac.map { String(format: "%02x", $0) }.joined()
    request.setValue(signature, forHTTPHeaderField: "X-Relay-Signature")
  }

  private func runtimeEndpointResolver() -> any RPCEndpointResolving {
    if let environment = runtimeEnvironment() {
      return environment.makeResolver()
    }
    return baseEndpointResolver
  }

  private func runtimeRelayConfig() -> RelayProxyConfig {
    if let environment = runtimeEnvironment() {
      return environment.relayConfig
    }
    return baseRelayConfig
  }

  private func runtimeEnvironment() -> RPCEnvironment? {
    guard let dynamicEnvironmentBundle else { return nil }
    return Self.makeEnvironment(bundle: dynamicEnvironmentBundle)
  }

  private static func makeEnvironment(
    bundle: Bundle = .main
  ) -> RPCEnvironment {
    let endpointConfig = RPCEndpointBuilderConfig(
      jsonRPCAPIKey: resolveSetting(
        infoPlistKeys: [RPCSecrets.jsonRPCKeyInfoPlistKey],
        bundle: bundle
      ),
      walletAPIKey: resolveSetting(
        infoPlistKeys: [RPCSecrets.walletAPIKeyInfoPlistKey],
        bundle: bundle
      ),
      addressActivityAPIKey: resolveSetting(
        infoPlistKeys: [RPCSecrets.addressActivityAPIKeyInfoPlistKey],
        bundle: bundle
      ),
      jsonRPCURLTemplate: RPCSecrets.jsonRPCURLTemplate,
      walletAPIURLTemplate: RPCSecrets.walletAPIURLTemplate,
      addressActivityAPIURLTemplate: RPCSecrets.addressActivityAPIURLTemplate,
      relayProxyBaseURL: resolveSetting(
        infoPlistKeys: [RPCSecrets.relayProxyBaseURLInfoPlistKey],
        bundle: bundle,
        defaultValue: RPCSecrets.relayProxyBaseURLDefault
      ),
      uploadProxyBaseURL: resolveSetting(
        infoPlistKeys: [RPCSecrets.uploadProxyBaseURLInfoPlistKey],
        bundle: bundle,
        defaultValue: RPCSecrets.uploadProxyBaseURLDefault
      ),
      relayProxyClientToken: resolveSetting(
        infoPlistKeys: [RPCSecrets.relayProxyClientTokenInfoPlistKey],
        bundle: bundle
      ),
      relayProxyHmacSecret: resolveSetting(
        infoPlistKeys: [RPCSecrets.relayProxyHmacSecretInfoPlistKey],
        bundle: bundle
      )
    )
    let mode = ChainSupportRuntime.resolveMode(bundle: bundle)
    let chainIDs = ChainSupportRuntime.resolveSupportedChainIDs(mode: mode, bundle: bundle)
    return RPCEnvironment(mode: mode, chainIDs: chainIDs, endpointConfig: endpointConfig)
  }

  private static func resolveSetting(
    infoPlistKeys: [String],
    bundle: Bundle,
    defaultValue: String = ""
  ) -> String {
    for infoPlistKey in infoPlistKeys {
      if let plist = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String {
        let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed
        }
      }
    }
    return defaultValue
  }
}
