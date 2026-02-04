import Foundation

public enum ENSError: Error {
  case invalidRPCURL
  case invalidAddress(String)
  case invalidName
  case ensUnavailable
  case nameUnavailable(String)
  case unsupportedResolver
  case missingResult(String)
}

extension ENSError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidRPCURL:
      return "ENS RPC URL is invalid."
    case .invalidAddress(let value):
      return "Invalid Ethereum address: \(value)."
    case .invalidName:
      return "Invalid ENS name."
    case .ensUnavailable:
      return "ENS is unavailable for the configured chain/provider."
    case .nameUnavailable(let label):
      return "ENS name is not available: \(label)."
    case .unsupportedResolver:
      return "Resolver does not support the requested ENS record type."
    case .missingResult(let key):
      return "Expected result key is missing: \(key)."
    }
  }
}
