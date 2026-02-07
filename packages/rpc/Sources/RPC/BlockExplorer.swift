import Foundation

public enum BlockExplorer {
  public static func addressURL(chainId: UInt64, address: String) -> URL? {
    ChainRegistry.resolve(chainID: chainId)?.addressURL(address: address)
  }

  public static func transactionURL(chainId: UInt64, transactionHash: String) -> URL? {
    ChainRegistry.resolve(chainID: chainId)?.transactionURL(transactionHash: transactionHash)
  }
}
