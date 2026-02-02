import Foundation
import Keychain
import Passkey
import Security
import SignHandler

public struct CreatedAccount: Equatable, Sendable {
  public let eoaAddress: String
  public let passkey: PasskeyPublicKey
  public let signedAuthorization: EIP7702AuthorizationSigned

  public init(
    eoaAddress: String,
    passkey: PasskeyPublicKey,
    signedAuthorization: EIP7702AuthorizationSigned
  ) {
    self.eoaAddress = eoaAddress
    self.passkey = passkey
    self.signedAuthorization = signedAuthorization
  }
}

public struct SignedInAccount: Equatable, Sendable {
  public let eoaAddress: String
  public let passkeyCredentialID: Data

  public init(eoaAddress: String, passkeyCredentialID: Data) {
    self.eoaAddress = eoaAddress
    self.passkeyCredentialID = passkeyCredentialID
  }
}

public enum AccountSetupError: Error {
  case invalidAddress
  case missingStoredPasskey
  case missingStoredAuthorization
  case inconsistentStoredIdentity
  case walletGenerationFailed(Error)
  case passkeyRegistrationFailed(Error)
  case authorizationSigningFailed(Error)
  case walletStorageFailed(Error)
  case passkeyStorageFailed(Error)
  case authorizationStorageFailed(Error)
  case passkeyAssertionFailed(Error)
  case authorizationRecoveryFailed(Error)
  case passkeyDecodeFailed(Error)
  case authorizationDecodeFailed(Error)
}

extension AccountSetupError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidAddress:
      return "Derived EOA address is invalid."
    case .missingStoredPasskey:
      return "No stored passkey public data found."
    case .missingStoredAuthorization:
      return "No stored signed authorization found."
    case .inconsistentStoredIdentity:
      return "Stored passkey identity does not match recovered authorization signer."
    case .walletGenerationFailed(let error):
      return "Failed to generate wallet material: \(error.localizedDescription)"
    case .passkeyRegistrationFailed(let error):
      return "Passkey registration failed: \(error.localizedDescription)"
    case .authorizationSigningFailed(let error):
      return "Failed to sign EIP-7702 authorization: \(error.localizedDescription)"
    case .walletStorageFailed(let error):
      return "Failed to persist wallet material locally: \(error.localizedDescription)"
    case .passkeyStorageFailed(let error):
      return "Failed to save passkey public data: \(error.localizedDescription)"
    case .authorizationStorageFailed(let error):
      return "Failed to save signed authorization: \(error.localizedDescription)"
    case .passkeyAssertionFailed(let error):
      return "Passkey assertion failed during sign-in: \(error.localizedDescription)"
    case .authorizationRecoveryFailed(let error):
      return "Failed to recover signer from signed authorization: \(error.localizedDescription)"
    case .passkeyDecodeFailed(let error):
      return "Stored passkey data could not be decoded: \(error.localizedDescription)"
    case .authorizationDecodeFailed(let error):
      return "Stored authorization data could not be decoded: \(error.localizedDescription)"
    }
  }
}

public protocol WalletMaterialStoring {
  func save(_ wallet: WalletMaterial) throws
  func read() throws -> WalletMaterial
}

public struct LocalWalletMaterialStore: WalletMaterialStoring {
  private let fileURL: URL

  public init(filename: String = "wallet-material.json") {
    let baseDirectory =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.fileURL = baseDirectory.appendingPathComponent(filename)
  }

  public func save(_ wallet: WalletMaterial) throws {
    let data = try JSONEncoder().encode(wallet)
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    try data.write(to: fileURL, options: .atomic)

#if os(iOS)
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var writableURL = fileURL
    try? writableURL.setResourceValues(resourceValues)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: fileURL.path
    )
#endif
  }

  public func read() throws -> WalletMaterial {
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode(WalletMaterial.self, from: data)
  }
}

public actor AccountSetupService {
  private enum KeychainAccount {
    static let passkeyPublic = "passkey.public"
    static let authorization = "auth.7702.signed"
  }

  private let walletFactory: WalletMaterialFactory
  private let passkeyService: PasskeyServicing
  private let keychain: KeychainStoring
  private let walletStore: WalletMaterialStoring
  private let keychainService: String
  private let relyingParty: PasskeyRelyingParty

  public init(
    walletFactory: WalletMaterialFactory = .init(),
    passkeyService: PasskeyServicing,
    keychain: KeychainStoring = KeychainStore(),
    walletStore: WalletMaterialStoring = LocalWalletMaterialStore(),
    keychainService: String = "com.peteranyaogu.metu",
    relyingParty: PasskeyRelyingParty = .init(rpID: "peteranyaogu.com", rpName: "peteranyaogu")
  ) {
    self.walletFactory = walletFactory
    self.passkeyService = passkeyService
    self.keychain = keychain
    self.walletStore = walletStore
    self.keychainService = keychainService
    self.relyingParty = relyingParty
  }

  public func createEOAAndPasskey(
    delegateAddress: String,
    chainId: UInt64 = 1,
    nonce: UInt64 = 0
  ) async throws -> CreatedAccount {
    let wallet: WalletMaterial
    do {
      wallet = try walletFactory.createNewEOA()
    } catch {
      throw AccountSetupError.walletGenerationFailed(error)
    }

    let userID = Data(UUID().uuidString.utf8)

    let passkey: PasskeyPublicKey
    do {
      passkey = try await passkeyService.register(
        rpId: relyingParty.rpID,
        rpName: relyingParty.rpName,
        challenge: randomChallenge(),
        userName: wallet.eoaAddress,
        userID: userID
      )
    } catch {
      throw AccountSetupError.passkeyRegistrationFailed(error)
    }

    let unsigned = EIP7702AuthorizationUnsigned(
      chainId: chainId,
      delegateAddress: delegateAddress,
      nonce: nonce
    )
    let signedAuthorization: EIP7702AuthorizationSigned
    do {
      signedAuthorization = try EIP7702AuthorizationCodec.signAuthorization(
        unsigned,
        privateKeyHex: wallet.privateKeyHex
      )
    } catch {
      throw AccountSetupError.authorizationSigningFailed(error)
    }

    do {
      try walletStore.save(wallet)
    } catch {
      throw AccountSetupError.walletStorageFailed(error)
    }

    do {
      try keychain.save(
        try JSONEncoder().encode(passkey),
        account: KeychainAccount.passkeyPublic,
        service: keychainService
      )
    } catch {
      throw AccountSetupError.passkeyStorageFailed(error)
    }

    do {
      try keychain.save(
        try JSONEncoder().encode(signedAuthorization),
        account: KeychainAccount.authorization,
        service: keychainService
      )
    } catch {
      throw AccountSetupError.authorizationStorageFailed(error)
    }

    return CreatedAccount(
      eoaAddress: wallet.eoaAddress,
      passkey: passkey,
      signedAuthorization: signedAuthorization
    )
  }

  public func signInWithPasskey() async throws -> SignedInAccount {
    let passkeyPublic = try storedPasskeyPublic()
    let signedAuthorization = try storedSignedAuthorization()

    do {
      _ = try await passkeyService.sign(rpId: relyingParty.rpID, payload: randomChallenge())
    } catch {
      throw AccountSetupError.passkeyAssertionFailed(error)
    }

    let recoveredAddress: String
    do {
      recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(signedAuthorization)
    } catch {
      throw AccountSetupError.authorizationRecoveryFailed(error)
    }
    guard recoveredAddress.caseInsensitiveCompare(passkeyPublic.userName) == .orderedSame else {
      throw AccountSetupError.inconsistentStoredIdentity
    }

    return SignedInAccount(
      eoaAddress: recoveredAddress,
      passkeyCredentialID: passkeyPublic.credentialID
    )
  }

  public func storedPasskeyPublic() throws -> PasskeyPublicKey {
    do {
      let data = try keychain.read(account: KeychainAccount.passkeyPublic, service: keychainService)
      do {
        return try JSONDecoder().decode(PasskeyPublicKey.self, from: data)
      } catch {
        throw AccountSetupError.passkeyDecodeFailed(error)
      }
    } catch KeychainStoreError.dataNotFound {
      throw AccountSetupError.missingStoredPasskey
    }
  }

  public func storedSignedAuthorization() throws -> EIP7702AuthorizationSigned {
    do {
      let data = try keychain.read(account: KeychainAccount.authorization, service: keychainService)
      do {
        return try JSONDecoder().decode(EIP7702AuthorizationSigned.self, from: data)
      } catch {
        throw AccountSetupError.authorizationDecodeFailed(error)
      }
    } catch KeychainStoreError.dataNotFound {
      throw AccountSetupError.missingStoredAuthorization
    }
  }

  public func storedWalletMaterial() throws -> WalletMaterial {
    try walletStore.read()
  }

  private func randomChallenge(length: Int = 32) -> Data {
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
  }
}
