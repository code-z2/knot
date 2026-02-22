import Foundation
import Web3Core
import web3swift

public struct WalletMaterialModel: Equatable, Sendable, Codable {
    public let mnemonic: String
    public let privateKeyHex: String
    public let eoaAddress: String

    public init(mnemonic: String, privateKeyHex: String, eoaAddress: String) {
        self.mnemonic = mnemonic
        self.privateKeyHex = privateKeyHex
        self.eoaAddress = eoaAddress
    }
}

public struct WalletMaterialFactory {
    public init() {}

    public func generateMnemonic(wordCount: Int = 12) throws -> String {
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
    }

    public func mnemonicToPrivateKey(
        _ mnemonic: String,
        password: String = "",
    ) throws -> String {
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
    }

    public func mnemonicToEOAAddress(
        _ mnemonic: String,
        password: String = "",
    ) throws -> String {
        guard let keystore = try? BIP32Keystore(mnemonics: mnemonic, password: password) else {
            throw WalletMaterialFactoryError.keystoreInitFailed
        }

        guard let address = keystore.addresses?.first else {
            throw WalletMaterialFactoryError.missingAddress
        }
        return address.address
    }

    public func createNewEOA(password: String = "") throws -> WalletMaterialModel {
        let mnemonic = try generateMnemonic(wordCount: 12)
        let privateKeyHex = try mnemonicToPrivateKey(mnemonic, password: password)
        let eoaAddress = try mnemonicToEOAAddress(mnemonic, password: password)
        return WalletMaterialModel(
            mnemonic: mnemonic,
            privateKeyHex: privateKeyHex,
            eoaAddress: eoaAddress,
        )
    }
}
