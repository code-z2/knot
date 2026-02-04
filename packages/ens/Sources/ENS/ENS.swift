import Foundation
import RPC

public final class ENSClient {
  let rpcClient: RPCClient

  public init(rpcClient: RPCClient = RPCClient()) {
    self.rpcClient = rpcClient
  }
}
