import Foundation
import RPC

public actor AAClient {
  private let core: AACore

  public init(rpcClient: RPCClient = RPCClient()) {
    self.core = AACore(rpcClient: rpcClient)
  }

  public func estimateGas(
    chainId: UInt64,
    from: String,
    to: String,
    data: String,
    value: String = "0x0"
  ) async throws -> String {
    try await core.estimateGas(chainId: chainId, from: from, to: to, data: data, value: value)
  }

  public func getFeeQuote(
    chainId: UInt64,
    request: RelayerTransactionRequest
  ) async throws -> RelayerFeeQuote {
    try await core.relayerGetFeeQuote(chainId: chainId, request: request)
  }

  public func sendTransaction(
    chainId: UInt64,
    request: RelayerTransactionRequest
  ) async throws -> RelayerSubmission {
    try await core.relayerSendTransaction(chainId: chainId, request: request)
  }

  public func sendTransactionSync(
    chainId: UInt64,
    request: RelayerTransactionRequest
  ) async throws -> RelayerSubmission {
    try await core.relayerSendTransactionSync(chainId: chainId, request: request)
  }

  public func getStatus(chainId: UInt64, id: String) async throws -> RelayerStatus {
    try await core.relayerGetStatus(chainId: chainId, id: id)
  }
}
