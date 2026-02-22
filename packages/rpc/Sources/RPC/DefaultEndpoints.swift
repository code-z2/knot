import Foundation

public struct RPCEndpointBuilderConfig: Sendable, Equatable {
    public let jsonRPCAPIKey: String
    public let walletAPIKey: String
    public let addressActivityAPIKey: String
    public let jsonRPCURLTemplate: String
    public let walletAPIURLTemplate: String
    public let addressActivityAPIURLTemplate: String
    public let relayProxyBaseURL: String
    public let uploadProxyBaseURL: String
    public let relayProxyClientToken: String
    public let relayProxyHmacSecret: String

    public init(
        jsonRPCAPIKey: String,
        walletAPIKey: String,
        addressActivityAPIKey: String,
        jsonRPCURLTemplate: String,
        walletAPIURLTemplate: String,
        addressActivityAPIURLTemplate: String,
        relayProxyBaseURL: String,
        uploadProxyBaseURL: String,
        relayProxyClientToken: String,
        relayProxyHmacSecret: String,
    ) {
        self.jsonRPCAPIKey = jsonRPCAPIKey
        self.walletAPIKey = walletAPIKey
        self.addressActivityAPIKey = addressActivityAPIKey
        self.jsonRPCURLTemplate = jsonRPCURLTemplate
        self.walletAPIURLTemplate = walletAPIURLTemplate
        self.addressActivityAPIURLTemplate = addressActivityAPIURLTemplate
        self.relayProxyBaseURL = relayProxyBaseURL
        self.uploadProxyBaseURL = uploadProxyBaseURL
        self.relayProxyClientToken = relayProxyClientToken
        self.relayProxyHmacSecret = relayProxyHmacSecret
    }
}

public func makeRPCDefaultEndpoints(config: RPCEndpointBuilderConfig) -> [UInt64: ChainEndpointsModel] {
    var endpointsByChain: [UInt64: ChainEndpointsModel] = [:]
    for definition in ChainRegistry.known {
        guard let endpoints = definition.makeEndpoints(config: config) else {
            continue
        }
        endpointsByChain[definition.chainID] = endpoints
    }
    return endpointsByChain
}
