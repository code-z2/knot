import Foundation

public struct RPCEnvironment: Sendable, Equatable {
  public let mode: ChainSupportMode
  public let chainIDs: [UInt64]
  public let endpointConfig: RPCEndpointBuilderConfig
  public let relayConfig: RelayProxyConfig

  public init(
    mode: ChainSupportMode,
    chainIDs: [UInt64]? = nil,
    endpointConfig: RPCEndpointBuilderConfig
  ) {
    self.mode = mode
    self.chainIDs = chainIDs ?? mode.defaultChainIDs
    self.endpointConfig = endpointConfig
    self.relayConfig = RelayProxyConfig(
      baseURL: endpointConfig.relayProxyBaseURL,
      uploadBaseURL: endpointConfig.uploadProxyBaseURL,
      clientToken: endpointConfig.relayProxyClientToken,
      hmacSecret: endpointConfig.relayProxyHmacSecret
    )
  }

  public var endpointsByChain: [UInt64: ChainEndpoints] {
    let defaults = makeRPCDefaultEndpoints(config: endpointConfig)
    let allowed = Set(chainIDs)
    return defaults.filter { allowed.contains($0.key) }
  }

  public func makeResolver() -> StaticRPCEndpointResolver {
    StaticRPCEndpointResolver(endpointsByChain: endpointsByChain)
  }
}
