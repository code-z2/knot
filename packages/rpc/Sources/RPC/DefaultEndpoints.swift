import Foundation

public enum RPCSecrets {
    public static let jsonRPCKeyInfoPlistKey = "JSONRPC_API_KEY"
    public static let walletAPIKeyInfoPlistKey = "ZERION_API_KEY"
    public static let addressActivityAPIKeyInfoPlistKey = "ZERION_API_KEY"
    public static let relayProxyBaseURLInfoPlistKey = "RELAY_PROXY_BASE_URL"
    public static let uploadProxyBaseURLInfoPlistKey = "UPLOAD_PROXY_BASE_URL"
    public static let relayProxyClientTokenInfoPlistKey = "CLIENT_TOKEN"
    public static let relayProxyHmacSecretInfoPlistKey = "RELAY_PROXY_HMAC_SECRET"

    // Hardcoded URL templates: edit here to swap providers globally.
    public static let jsonRPCURLTemplate = "https://{slug}.g.alchemy.com/v2/{apiKey}"
    public static let walletAPIURLTemplate =
        "https://api.zerion.io/v1/wallets/{walletAddress}/positions/"
    public static let addressActivityAPIURLTemplate =
        "https://api.zerion.io/v1/wallets/{walletAddress}/transactions/"
    public static let relayProxyBaseURLDefault = "https://relay.knot.fi"
    public static let uploadProxyBaseURLDefault = "https://upload.knot.fi"
}

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

public func makeRPCDefaultEndpoints(config: RPCEndpointBuilderConfig) -> [UInt64: ChainEndpoints] {
    var endpointsByChain: [UInt64: ChainEndpoints] = [:]
    for definition in ChainRegistry.known {
        guard let endpoints = definition.makeEndpoints(config: config) else {
            continue
        }
        endpointsByChain[definition.chainID] = endpoints
    }
    return endpointsByChain
}
