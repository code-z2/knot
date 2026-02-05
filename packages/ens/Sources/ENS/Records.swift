import Foundation
import Transactions
import web3swift

extension ENSClient {
  public func addRecord(_ request: AddRecordRequest) async throws -> Call {
    try await setTextRecord(
      name: request.name,
      recordKey: request.recordKey,
      recordValue: request.recordValue
    )
  }

  public func updateRecord(_ request: UpdateRecordRequest) async throws -> Call {
    try await setTextRecord(
      name: request.name,
      recordKey: request.recordKey,
      recordValue: request.recordValue
    )
  }

  public func textRecord(_ request: TextRecordRequest) async throws -> String {
    let (normalizedName, _, resolver) = try await resolvedTextCapableResolver(
      forName: request.name
    )

    return try await resolver.getTextData(
      forNode: normalizedName,
      key: request.recordKey
    )
  }

  private func setTextRecord(
    name: String,
    recordKey: String,
    recordValue: String
  ) async throws -> Call {
    let (normalizedName, web3, resolver) = try await resolvedTextCapableResolver(forName: name)

    guard let nodeHash = NameHash.nameHash(normalizedName) else {
      throw ENSError.invalidName
    }

    return try makeWritePayload(
      web3: web3,
      abi: Web3.Utils.resolverABI,
      to: resolver.resolverContractAddress,
      method: "setText",
      parameters: [nodeHash, recordKey, recordValue]
    )
  }

  private func resolvedTextCapableResolver(
    forName name: String
  ) async throws -> (normalizedName: String, web3: Web3, resolver: web3swift.ENS.Resolver) {
    let normalizedName = Self.normalizedENSName(name)
    guard !normalizedName.isEmpty else { throw ENSError.invalidName }

    let web3 = try await rpcClient.getWeb3Client(chainId: 1)
    guard let ens = web3swift.ENS(web3: web3) else {
      throw ENSError.ensUnavailable
    }

    let resolver = try await ens.registry.getResolver(forDomain: normalizedName)
    let supportsText = try await resolver.supportsInterface(interfaceID: .text)
    guard supportsText else { throw ENSError.unsupportedResolver }

    return (normalizedName, web3, resolver)
  }
}
