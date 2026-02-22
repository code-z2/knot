import Foundation

public enum ExecuteXPlannerError: Error {
    case emptyLeaves

    case duplicateExecuteLeafChain(UInt64)

    case missingAuthorization(chainId: UInt64)
}

extension ExecuteXPlannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyLeaves:
            "At least one ExecuteX leaf is required."

        case let .duplicateExecuteLeafChain(chainId):
            "ExecuteX leaves must be unique per chain. Duplicate chain: \(chainId)."

        case let .missingAuthorization(chainId):
            "Missing EIP-7702 authorization for uninitialized chain \(chainId)."
        }
    }
}
