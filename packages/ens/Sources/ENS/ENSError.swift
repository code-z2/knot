import Foundation

public enum ENSError: Error {
    case invalidRPCURL
    case invalidAddress(String)
    case invalidName
    case ensUnavailable
    case nameUnavailable(String)
    case missingResult(String)
}

extension ENSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRPCURL:
            "ENS RPC URL is invalid."
        case let .invalidAddress(value):
            "Invalid Ethereum address: \(value)."
        case .invalidName:
            "Invalid ENS name."
        case .ensUnavailable:
            "ENS is unavailable for the configured chain/provider."
        case let .nameUnavailable(label):
            "ENS name is not available: \(label)."
        case let .missingResult(key):
            "Expected result key is missing: \(key)."
        }
    }
}
