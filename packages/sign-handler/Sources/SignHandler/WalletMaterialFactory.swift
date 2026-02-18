import Foundation

public struct WalletMaterial: Equatable, Sendable, Codable {
    public let mnemonic: String
    public let privateKeyHex: String
    public let eoaAddress: String

    public init(mnemonic: String, privateKeyHex: String, eoaAddress: String) {
        self.mnemonic = mnemonic
        self.privateKeyHex = privateKeyHex
        self.eoaAddress = eoaAddress
    }
}

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

public struct WalletMaterialFactory {
    public init() {}

    public func generateMnemonic(wordCount: Int = 12) throws -> String {
        #if canImport(web3swift) && canImport(Web3Core)
            let bits = switch wordCount {
            case 12: 128
            case 15: 160
            case 18: 192
            case 21: 224
            case 24: 256
            default: 128
            }

            guard let mnemonic = try? BIP39.generateMnemonics(bitsOfEntropy: bits), !mnemonic.isEmpty else {
                throw WalletMaterialFactoryError.mnemonicGenerationFailed
            }
            return mnemonic
        #else
            throw WalletMaterialFactoryError.web3swiftUnavailable
        #endif
    }

    public func mnemonicToPrivateKey(
        _ mnemonic: String,
        password: String = "",
    ) throws -> String {
        #if canImport(web3swift) && canImport(Web3Core)
            guard let keystore = try? BIP32Keystore(mnemonics: mnemonic, password: password) else {
                throw WalletMaterialFactoryError.keystoreInitFailed
            }

            guard let address = keystore.addresses?.first else {
                throw WalletMaterialFactoryError.missingAddress
            }

            guard let privateKeyData = try? keystore.UNSAFE_getPrivateKeyData(password: password, account: address) else {
                throw WalletMaterialFactoryError.privateKeyExtractionFailed
            }
            return privateKeyData.toHexString().addHexPrefix()
        #else
            throw WalletMaterialFactoryError.web3swiftUnavailable
        #endif
    }

    public func mnemonicToEOAAddress(
        _ mnemonic: String,
        password: String = "",
    ) throws -> String {
        #if canImport(web3swift) && canImport(Web3Core)
            guard let keystore = try? BIP32Keystore(mnemonics: mnemonic, password: password) else {
                throw WalletMaterialFactoryError.keystoreInitFailed
            }

            guard let address = keystore.addresses?.first else {
                throw WalletMaterialFactoryError.missingAddress
            }
            return address.address
        #else
            throw WalletMaterialFactoryError.web3swiftUnavailable
        #endif
    }

    public func createNewEOA(password: String = "") throws -> WalletMaterial {
        #if canImport(web3swift) && canImport(Web3Core)
            let mnemonic = try generateMnemonic(wordCount: 12)
            let privateKeyHex = try mnemonicToPrivateKey(mnemonic, password: password)
            let eoaAddress = try mnemonicToEOAAddress(mnemonic, password: password)
            return WalletMaterial(
                mnemonic: mnemonic,
                privateKeyHex: privateKeyHex,
                eoaAddress: eoaAddress,
            )
        #else
            throw WalletMaterialFactoryError.web3swiftUnavailable
        #endif
    }
}

#if canImport(Web3Core)
    import Web3Core
#endif
#if canImport(web3swift)
    import web3swift
#endif
