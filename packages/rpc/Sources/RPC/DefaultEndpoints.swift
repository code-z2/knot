import Foundation

public enum RPCSecrets {
  public static let jsonRPCKeyInfoPlistKey = "JSONRPC_API_KEY"
  public static let bundlerKeyInfoPlistKey = "BUNDLER_API_KEY"
  public static let paymasterKeyInfoPlistKey = "PAYMASTER_API_KEY"
  public static let walletAPIKeyInfoPlistKey = "WALLET_API_KEY"
  public static let addressActivityAPIKeyInfoPlistKey = "TRANSACTIONS_API_KEY"

  // Hardcoded URL templates: edit here to swap providers globally.
  public static let jsonRPCURLTemplate = "https://{slug}.g.alchemy.com/v2/{apiKey}"
  public static let bundlerURLTemplate = "https://api.gelato.cloud/rpc/{chainId}?apiKey={apiKey}"
  public static let paymasterURLTemplate = "https://api.pimlico.io/v2/{chainId}/rpc?apikey={apiKey}"
  public static let walletAPIURLTemplate =
    "https://api.covalenthq.com/v1/allchains/address/{walletAddress}/balances/"
  public static let addressActivityAPIURLTemplate =
    "https://api.covalenthq.com/v1/address/{walletAddress}/activity/"
  public static let allchainsTransactionsURLBase =
    "https://api.covalenthq.com/v1/allchains/transactions/"
}

public struct RPCEndpointBuilderConfig: Sendable, Equatable {
  public let jsonRPCAPIKey: String
  public let bundlerAPIKey: String
  public let paymasterAPIKey: String
  public let walletAPIKey: String
  public let addressActivityAPIKey: String
  public let jsonRPCURLTemplate: String
  public let bundlerURLTemplate: String
  public let paymasterURLTemplate: String
  public let walletAPIURLTemplate: String
  public let addressActivityAPIURLTemplate: String

  public init(
    jsonRPCAPIKey: String,
    bundlerAPIKey: String,
    paymasterAPIKey: String,
    walletAPIKey: String,
    addressActivityAPIKey: String,
    jsonRPCURLTemplate: String,
    bundlerURLTemplate: String,
    paymasterURLTemplate: String,
    walletAPIURLTemplate: String,
    addressActivityAPIURLTemplate: String
  ) {
    self.jsonRPCAPIKey = jsonRPCAPIKey
    self.bundlerAPIKey = bundlerAPIKey
    self.paymasterAPIKey = paymasterAPIKey
    self.walletAPIKey = walletAPIKey
    self.addressActivityAPIKey = addressActivityAPIKey
    self.jsonRPCURLTemplate = jsonRPCURLTemplate
    self.bundlerURLTemplate = bundlerURLTemplate
    self.paymasterURLTemplate = paymasterURLTemplate
    self.walletAPIURLTemplate = walletAPIURLTemplate
    self.addressActivityAPIURLTemplate = addressActivityAPIURLTemplate
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
