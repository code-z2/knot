import Foundation
import Transactions
import web3swift

public extension ENSClient {
    func setTextRecord(_ request: TextRecordRequestModel) async throws -> Call {
        let context = try await universalResolverContext(forName: request.name)

        return try makeWritePayload(
            web3: context.web3,
            abi: Web3.Utils.resolverABI,
            to: context.resolverAddress,
            method: "setText",
            parameters: [context.nodeHash, request.recordKey, request.recordValue ?? ""],
        )
    }

    func textRecord(_ request: TextRecordRequestModel) async throws -> String {
        let context = try await universalResolverContext(forName: request.name)
        let encodedCall = try makeCallData(
            web3: context.web3,
            abi: Web3.Utils.resolverABI,
            method: "text",
            parameters: [context.nodeHash, request.recordKey],
        )
        let resolved = try await universalResolve(
            web3: context.web3,
            normalizedName: context.normalizedName,
            callData: encodedCall,
        )
        guard let text = Self.abiDecodeString(from: resolved) else { throw ENSError.ensUnavailable }
        return text
    }
}
