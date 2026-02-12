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
}
