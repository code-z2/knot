import Foundation

public enum BlockExplorer {
  public static func addressURL(chainId: UInt64, address: String) -> URL? {
    guard let baseURL = baseURL(chainId: chainId) else { return nil }
    let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    return URL(string: "\(baseURL)/address/\(normalized)")
  }

  public static func transactionURL(chainId: UInt64, transactionHash: String) -> URL? {
    guard let baseURL = baseURL(chainId: chainId) else { return nil }
    let normalized = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    return URL(string: "\(baseURL)/tx/\(normalized)")
  }

  private static func baseURL(chainId: UInt64) -> String? {
    switch chainId {
    case 1:
      return "https://etherscan.io"
    case 10:
      return "https://optimistic.etherscan.io"
    case 137:
      return "https://polygonscan.com"
    case 56:
      return "https://bscscan.com"
    case 8453:
      return "https://basescan.org"
    case 42161:
      return "https://arbiscan.io"
    case 84532:
      return "https://sepolia.basescan.org"
    case 11155111:
      return "https://sepolia.etherscan.io"
    default:
      return nil
    }
  }
}
