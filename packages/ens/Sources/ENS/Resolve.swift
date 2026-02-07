import Foundation
import Web3Core
import web3swift

extension ENSClient {
  public func resolveName(_ request: ResolveNameRequest) async throws -> String {
    let name = Self.normalizedENSName(request.name)
    guard !name.isEmpty else { throw ENSError.invalidName }
    let context = try await universalResolverContext(forName: name)

    let encodedCall = try makeCallData(
      web3: context.web3,
      abi: Web3.Utils.resolverABI,
      method: "addr",
      parameters: [context.nodeHash]
    )
    let resolved = try await universalResolve(
      web3: context.web3,
      normalizedName: context.normalizedName,
      callData: encodedCall
    )
    guard let address = Self.abiDecodeAddress(from: resolved) else {
      throw ENSError.ensUnavailable
    }
    guard address.address.lowercased() != Self.zeroAddressHex else {
      throw ENSError.ensUnavailable
    }
    return address.address
  }

  public func reverseAddress(_ request: ReverseAddressRequest) async throws -> String {
    guard let address = EthereumAddress(request.address) else {
      throw ENSError.invalidAddress(request.address)
    }

    let reverseNode = Self.reverseNode(for: address)
    let context = try await universalResolverContext(forName: reverseNode)

    let encodedCall = try makeCallData(
      web3: context.web3,
      abi: Web3.Utils.resolverABI,
      method: "name",
      parameters: [context.nodeHash]
    )
    let resolved = try await universalResolve(
      web3: context.web3,
      normalizedName: context.normalizedName,
      callData: encodedCall
    )
    guard let name = Self.abiDecodeString(from: resolved) else {
      throw ENSError.ensUnavailable
    }
    let normalized = Self.normalizedENSName(name)
    guard !normalized.isEmpty else { throw ENSError.ensUnavailable }
    return normalized
  }
}
