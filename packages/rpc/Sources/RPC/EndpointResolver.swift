import Foundation

public protocol RPCEndpointResolving: Sendable {
  func endpoints(for chainId: UInt64) throws -> ChainEndpoints
  func supportedChains() -> [UInt64]
}

public struct StaticRPCEndpointResolver: RPCEndpointResolving, Sendable {
  public let endpointsByChain: [UInt64: ChainEndpoints]

  public init(endpointsByChain: [UInt64: ChainEndpoints]) {
    self.endpointsByChain = endpointsByChain
  }

  public func endpoints(for chainId: UInt64) throws -> ChainEndpoints {
    guard let endpoints = endpointsByChain[chainId] else {
      throw RPCError.unsupportedChain(chainId)
    }
    return endpoints
  }

  public func supportedChains() -> [UInt64] {
    endpointsByChain.keys.sorted()
  }
}
