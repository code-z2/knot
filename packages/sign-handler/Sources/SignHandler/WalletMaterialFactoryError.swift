import Foundation

public enum WalletMaterialFactoryError: Error {
    case web3swiftUnavailable

    case mnemonicGenerationFailed

    case keystoreInitFailed

    case missingAddress

    case privateKeyExtractionFailed
}

extension WalletMaterialFactoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .web3swiftUnavailable:
            "Wallet generation dependency is unavailable (web3swift/Web3Core)."

        case .mnemonicGenerationFailed:
            "Failed to generate a mnemonic phrase."

        case .keystoreInitFailed:
            "Failed to initialize keystore from mnemonic."

        case .missingAddress:
            "No account address was derived from the keystore."

        case .privateKeyExtractionFailed:
            "Failed to extract private key from derived account."
        }
    }
}
