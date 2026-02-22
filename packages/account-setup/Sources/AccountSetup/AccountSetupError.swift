import Foundation

public enum AccountSetupError: Error {
    case missingStoredPasskey

    case walletGenerationFailed(Error)

    case passkeyRegistrationFailed(Error)

    case walletStorageFailed(Error)

    case authorizationStorageFailed(Error)

    case passkeyAssertionFailed(Error)

    case authorizationDecodeFailed(Error)

    case accumulatorDerivationFailed(Error)

    case missingStoredAccumulator(String)

    case missingStoredAccount(String)
}

extension AccountSetupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingStoredPasskey:
            "No stored passkey public data found."

        case let .walletGenerationFailed(error):
            "Failed to generate wallet material: \(error.localizedDescription)"

        case let .passkeyRegistrationFailed(error):
            "Passkey registration failed: \(error.localizedDescription)"

        case let .walletStorageFailed(error):
            "Failed to persist wallet material locally: \(error.localizedDescription)"

        case let .authorizationStorageFailed(error):
            "Failed to save signed authorization: \(error.localizedDescription)"

        case let .passkeyAssertionFailed(error):
            "Passkey assertion failed during sign-in: \(error.localizedDescription)"

        case let .authorizationDecodeFailed(error):
            "Stored authorization data could not be decoded: \(error.localizedDescription)"

        case let .accumulatorDerivationFailed(error):
            "Failed to derive accumulator address: \(error.localizedDescription)"

        case let .missingStoredAccumulator(eoaAddress):
            "No stored accumulator address found for EOA \(eoaAddress)."

        case let .missingStoredAccount(eoaAddress):
            "No stored account found for EOA \(eoaAddress)."
        }
    }
}
