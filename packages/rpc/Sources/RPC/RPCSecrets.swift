import Foundation

public enum RPCSecrets {
    public static let jsonRPCKeyInfoPlistKey = "JSONRPC_API_KEY"

    public static let walletAPIKeyInfoPlistKey = "ZERION_API_KEY"

    public static let addressActivityAPIKeyInfoPlistKey = "ZERION_API_KEY"

    public static let relayProxyBaseURLInfoPlistKey = "RELAY_PROXY_BASE_URL"

    public static let uploadProxyBaseURLInfoPlistKey = "UPLOAD_PROXY_BASE_URL"

    public static let relayProxyClientTokenInfoPlistKey = "CLIENT_TOKEN"

    public static let relayProxyHmacSecretInfoPlistKey = "RELAY_PROXY_HMAC_SECRET"

    /// Hardcoded URL templates: edit here to swap providers globally.
    public static let jsonRPCURLTemplate = "https://{slug}.g.alchemy.com/v2/{apiKey}"

    public static let walletAPIURLTemplate =
        "https://api.zerion.io/v1/wallets/{walletAddress}/positions/"

    public static let addressActivityAPIURLTemplate =
        "https://api.zerion.io/v1/wallets/{walletAddress}/transactions/"

    public static let relayProxyBaseURLDefault = "https://relay.knot.fi"

    public static let uploadProxyBaseURLDefault = "https://upload.knot.fi"
}
