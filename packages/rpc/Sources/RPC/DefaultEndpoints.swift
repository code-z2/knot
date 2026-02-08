import Foundation

public enum RPCSecrets {
  public static let jsonRPCKeyInfoPlistKey = "JSONRPC_API_KEY"
  public static let bundlerKeyInfoPlistKey = "BUNDLER_API_KEY"
  public static let paymasterKeyInfoPlistKey = "PAYMASTER_API_KEY"
  public static let walletAPIKeyInfoPlistKey = "WALLET_API_KEY"
  public static let transactionsAPIKeyInfoPlistKey = "TRANSACTIONS_API_KEY"

  // Hardcoded URL templates: edit here to swap providers globally.
  public static let jsonRPCURLTemplate = "https://{slug}.g.alchemy.com/v2/{apiKey}"
  public static let bundlerURLTemplate = "https://api.gelato.cloud/rpc/{chainId}?apiKey={apiKey}"
  public static let paymasterURLTemplate = "https://api.pimlico.io/v2/{chainId}/rpc?apikey={apiKey}"
  public static let walletAPIURLTemplate =
    "https://api.covalenthq.com/v1/allchains/address/{walletAddress}/balances/"
  public static let transactionsAPIURLTemplate =
    "https://api.covalenthq.com/v1/address/{walletAddress}/activity/"
  public static let allchainsTransactionsURLBase =
    "https://api.covalenthq.com/v1/allchains/transactions/"
}

public struct RPCEndpointBuilderConfig: Sendable, Equatable {
  public let jsonRPCAPIKey: String
  public let bundlerAPIKey: String
  public let paymasterAPIKey: String
  public let walletAPIKey: String
  public let transactionsAPIKey: String
  public let jsonRPCURLTemplate: String
  public let bundlerURLTemplate: String
  public let paymasterURLTemplate: String
  public let walletAPIURLTemplate: String
  public let transactionsAPIURLTemplate: String

  public init(
    jsonRPCAPIKey: String,
    bundlerAPIKey: String,
    paymasterAPIKey: String,
    walletAPIKey: String,
    transactionsAPIKey: String,
    jsonRPCURLTemplate: String,
    bundlerURLTemplate: String,
    paymasterURLTemplate: String,
    walletAPIURLTemplate: String,
    transactionsAPIURLTemplate: String
  ) {
    self.jsonRPCAPIKey = jsonRPCAPIKey
    self.bundlerAPIKey = bundlerAPIKey
    self.paymasterAPIKey = paymasterAPIKey
    self.walletAPIKey = walletAPIKey
    self.transactionsAPIKey = transactionsAPIKey
    self.jsonRPCURLTemplate = jsonRPCURLTemplate
    self.bundlerURLTemplate = bundlerURLTemplate
    self.paymasterURLTemplate = paymasterURLTemplate
    self.walletAPIURLTemplate = walletAPIURLTemplate
    self.transactionsAPIURLTemplate = transactionsAPIURLTemplate
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
