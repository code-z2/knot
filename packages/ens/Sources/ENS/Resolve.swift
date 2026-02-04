import Foundation
import Web3Core
import web3swift

extension ENSClient {
  public func resolveName(_ request: ResolveNameRequest) async throws -> String {
    let name = Self.normalizedENSName(request.name)
    guard !name.isEmpty else { throw ENSError.invalidName }

    let web3 = try await rpcClient.getWeb3Client(chainId: 1)
    guard let ens = web3swift.ENS(web3: web3) else {
      throw ENSError.ensUnavailable
    }

    let address = try await ens.getAddress(forNode: name)
    return address.address
  }

  public func reverseAddress(_ request: ReverseAddressRequest) async throws -> String {
    guard let address = EthereumAddress(request.address) else {
      throw ENSError.invalidAddress(request.address)
    }

    let web3 = try await rpcClient.getWeb3Client(chainId: 1)
    guard let ens = web3swift.ENS(web3: web3) else {
      throw ENSError.ensUnavailable
    }

    let reverseNode = Self.reverseNode(for: address)
    let name = try await ens.getName(forNode: reverseNode)
    return Self.normalizedENSName(name)
  }
}
