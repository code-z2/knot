import Foundation

public protocol RPCEndpointResolverProviding: Sendable {
    func endpoints(for chainId: UInt64) throws -> ChainEndpointsModel
    func supportedChains() -> [UInt64]
}

public struct StaticRPCEndpointResolverService: RPCEndpointResolverProviding, Sendable {
    public let endpointsByChain: [UInt64: ChainEndpointsModel]

    public init(endpointsByChain: [UInt64: ChainEndpointsModel]) {
        self.endpointsByChain = endpointsByChain
    }

    public func endpoints(for chainId: UInt64) throws -> ChainEndpointsModel {
        guard let endpoints = endpointsByChain[chainId] else {
            throw RPCError.unsupportedChain(chainId)
        }
        return endpoints
    }

    public func supportedChains() -> [UInt64] {
        endpointsByChain.keys.sorted()
    }
}
