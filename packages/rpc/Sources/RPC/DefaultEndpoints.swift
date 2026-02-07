import Foundation

public enum RPCSecrets {
  public static let gelatoKeyInfoPlistKey = "GELATO_API_KEY"
  public static let pimlicoKeyInfoPlistKey = "PIMLICO_API_KEY"
  public static let gelatoKeyEnv = "GELATO_API_KEY"
  public static let pimlicoKeyEnv = "PIMLICO_API_KEY"
}

public func makeRPCDefaultEndpoints(gelatoAPIKey: String, pimlicoAPIKey: String) -> [UInt64: ChainEndpoints] {
  return [
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
      bundlerURL: makeGelatoURL(chainId: 8453, apiKey: gelatoAPIKey),
      paymasterURL: makePimlicoURL(chainId: 8453, apiKey: pimlicoAPIKey)
    ),
    84532: ChainEndpoints(
      rpcURL: "https://sepolia.base.org",
      bundlerURL: makeGelatoURL(chainId: 84532, apiKey: gelatoAPIKey),
      paymasterURL: makePimlicoURL(chainId: 84532, apiKey: pimlicoAPIKey)
    ),
    11155111: ChainEndpoints(
      rpcURL: "https://ethereum-sepolia-rpc.publicnode.com",
      bundlerURL: makeGelatoURL(chainId: 11155111, apiKey: gelatoAPIKey),
      paymasterURL: makePimlicoURL(chainId: 11155111, apiKey: pimlicoAPIKey)
    ),
  ]
}

private func makeGelatoURL(chainId: UInt64, apiKey: String) -> String {
  let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !key.isEmpty else { return "" }
  return "https://api.gelato.cloud/rpc/\(chainId)?apiKey=\(key)"
}

private func makePimlicoURL(chainId: UInt64, apiKey: String) -> String {
  let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !key.isEmpty else { return "" }
  return "https://api.pimlico.io/v2/\(chainId)/rpc?apikey=\(key)"
}
