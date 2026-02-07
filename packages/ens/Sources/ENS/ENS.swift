import Foundation
import RPC

public final class ENSClient {
  let rpcClient: RPCClient
  public let configuration: ENSConfiguration

  public init(
    rpcClient: RPCClient = RPCClient(),
    configuration: ENSConfiguration = .sepolia
  ) {
    self.rpcClient = rpcClient
    self.configuration = configuration
  }
}
