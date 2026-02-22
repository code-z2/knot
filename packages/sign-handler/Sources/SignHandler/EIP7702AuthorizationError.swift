import Foundation

public enum EIP7702AuthorizationError: Error {
    case signingUnavailable

    case invalidPrivateKey

    case malformedSignature

    case recoveryUnavailable

    case recoveryFailed
}

extension EIP7702AuthorizationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .signingUnavailable:
            "Authorization signing is unavailable (web3swift/Web3Core missing)."

        case .invalidPrivateKey:
            "Invalid private key format for authorization signing."

        case .malformedSignature:
            "Authorization signature payload is malformed."

        case .recoveryUnavailable:
            "Authorization recovery is unavailable (web3swift/Web3Core missing)."

        case .recoveryFailed:
            "Failed to recover signer address from signed authorization."
        }
    }
}
