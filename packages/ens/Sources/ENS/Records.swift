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
    let context = try await universalResolverContext(forName: request.name)
    let encodedCall = try makeCallData(
      web3: context.web3,
      abi: Web3.Utils.resolverABI,
      method: "text",
      parameters: [context.nodeHash, request.recordKey]
    )
    let resolved = try await universalResolve(
      web3: context.web3,
      normalizedName: context.normalizedName,
      callData: encodedCall
    )
    guard let text = Self.abiDecodeString(from: resolved) else { throw ENSError.ensUnavailable }
    return text
  }

  private func setTextRecord(
    name: String,
    recordKey: String,
    recordValue: String
  ) async throws -> Call {
    let context = try await universalResolverContext(forName: name)

    return try makeWritePayload(
      web3: context.web3,
      abi: Web3.Utils.resolverABI,
      to: context.resolverAddress,
      method: "setText",
      parameters: [context.nodeHash, recordKey, recordValue]
    )
  }
}
