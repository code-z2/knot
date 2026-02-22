import BigInt
import Foundation
import web3swift

public actor RPCClient {
    let baseEndpointResolver: any RPCEndpointResolverProviding
    let baseRelayConfig: RelayProxyConfigModel
    let dynamicEnvironmentBundle: Bundle?
    let transport: any JSONRPCTransportProviding
    var requestID: Int = 1

    public init(
        environment: RPCEnvironment,
        transport: any JSONRPCTransportProviding = URLSessionJSONRPCTransportService(),
    ) {
        baseEndpointResolver = environment.makeResolver()
        baseRelayConfig = environment.relayConfig
        dynamicEnvironmentBundle = nil
        self.transport = transport
    }

    public init(
        resolver: any RPCEndpointResolverProviding,
        relayConfig: RelayProxyConfigModel = .init(),
        transport: any JSONRPCTransportProviding = URLSessionJSONRPCTransportService(),
    ) {
        baseEndpointResolver = resolver
        baseRelayConfig = relayConfig
        dynamicEnvironmentBundle = nil
        self.transport = transport
    }

    public init(
        bundle: Bundle = .main,
        transport: any JSONRPCTransportProviding = URLSessionJSONRPCTransportService(),
    ) {
        let environment = Self.makeEnvironment(bundle: bundle)
        baseEndpointResolver = environment.makeResolver()
        baseRelayConfig = environment.relayConfig
        dynamicEnvironmentBundle = bundle
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
        responseType: Response.Type = Response.self,
    ) async throws -> Response {
        let rpc = try getRpcUrl(chainId: chainId)
        return try await makeJSONRPCCall(
            urlString: rpc,
            method: method,
            params: params,
            responseType: responseType,
        )
    }

    public func getCode(chainId: UInt64, address: String, block: String = "latest") async throws
        -> String
    {
        try await makeRpcCall(
            chainId: chainId,
            method: "eth_getCode",
            params: [AnyCodable(address), AnyCodable(block)],
            responseType: String.self,
        )
    }

    func makeJSONRPCCall<Response: Decodable>(
        urlString: String,
        method: String,
        params: [AnyCodable] = [],
        responseType: Response.Type = Response.self,
    ) async throws -> Response {
        let id = requestID
        requestID += 1

        return try await transport.send(
            urlString: urlString,
            method: method,
            params: params,
            requestID: id,
            responseType: responseType,
        )
    }

    func runtimeEndpointResolver() -> any RPCEndpointResolverProviding {
        if let environment = runtimeEnvironment() {
            return environment.makeResolver()
        }
        return baseEndpointResolver
    }

    func runtimeRelayConfig() -> RelayProxyConfigModel {
        if let environment = runtimeEnvironment() {
            return environment.relayConfig
        }
        return baseRelayConfig
    }

    func runtimeEnvironment() -> RPCEnvironment? {
        guard let dynamicEnvironmentBundle else { return nil }
        return Self.makeEnvironment(bundle: dynamicEnvironmentBundle)
    }

    static func makeEnvironment(
        bundle: Bundle = .main,
    ) -> RPCEnvironment {
        let endpointConfig = RPCEndpointBuilderConfig(
            jsonRPCAPIKey: resolveSetting(
                infoPlistKeys: [RPCSecrets.jsonRPCKeyInfoPlistKey],
                bundle: bundle,
            ),
            walletAPIKey: resolveSetting(
                infoPlistKeys: [RPCSecrets.walletAPIKeyInfoPlistKey],
                bundle: bundle,
            ),
            addressActivityAPIKey: resolveSetting(
                infoPlistKeys: [RPCSecrets.addressActivityAPIKeyInfoPlistKey],
                bundle: bundle,
            ),
            jsonRPCURLTemplate: RPCSecrets.jsonRPCURLTemplate,
            walletAPIURLTemplate: RPCSecrets.walletAPIURLTemplate,
            addressActivityAPIURLTemplate: RPCSecrets.addressActivityAPIURLTemplate,
            relayProxyBaseURL: resolveSetting(
                infoPlistKeys: [RPCSecrets.relayProxyBaseURLInfoPlistKey],
                bundle: bundle,
                defaultValue: RPCSecrets.relayProxyBaseURLDefault,
            ),
            uploadProxyBaseURL: resolveSetting(
                infoPlistKeys: [RPCSecrets.uploadProxyBaseURLInfoPlistKey],
                bundle: bundle,
                defaultValue: RPCSecrets.uploadProxyBaseURLDefault,
            ),
            relayProxyClientToken: resolveSetting(
                infoPlistKeys: [RPCSecrets.relayProxyClientTokenInfoPlistKey],
                bundle: bundle,
            ),
            relayProxyHmacSecret: resolveSetting(
                infoPlistKeys: [RPCSecrets.relayProxyHmacSecretInfoPlistKey],
                bundle: bundle,
            ),
        )
        let mode = ChainSupportRuntime.resolveMode(bundle: bundle)
        let chainIDs = ChainSupportRuntime.resolveSupportedChainIDs(mode: mode, bundle: bundle)
        return RPCEnvironment(mode: mode, chainIDs: chainIDs, endpointConfig: endpointConfig)
    }

    static func resolveSetting(
        infoPlistKeys: [String],
        bundle: Bundle,
        defaultValue: String = "",
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
