import Foundation

public let rpcDefaultEndpoints: [UInt64: ChainEndpoints] = [
  1: ChainEndpoints(
    rpcURL: "https://eth.llamarpc.com",
    bundlerURL: "",
    paymasterURL: ""
  ),
  10: ChainEndpoints(
    rpcURL: "https://optimism.llamarpc.com",
    bundlerURL: "",
    paymasterURL: ""
  ),
  137: ChainEndpoints(
    rpcURL: "https://polygon.llamarpc.com",
    bundlerURL: "",
    paymasterURL: ""
  ),
  8453: ChainEndpoints(
    rpcURL: "https://base.llamarpc.com",
    bundlerURL: "",
    paymasterURL: ""
  ),
]
