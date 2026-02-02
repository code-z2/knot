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
    try? fileURL.setResourceValues(resourceValues)
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
    let wallet = try walletFactory.createNewEOA()
    let userID = Data(UUID().uuidString.utf8)

    let passkey = try await passkeyService.register(
      rpId: relyingParty.rpID,
      rpName: relyingParty.rpName,
      challenge: randomChallenge(),
      userName: wallet.eoaAddress,
      userID: userID
    )

    let unsigned = EIP7702AuthorizationUnsigned(
      chainId: chainId,
      delegateAddress: delegateAddress,
      nonce: nonce
    )
    let signedAuthorization = try EIP7702AuthorizationCodec.signAuthorization(
      unsigned,
      privateKeyHex: wallet.privateKeyHex
    )

    try walletStore.save(wallet)
    try keychain.save(
      try JSONEncoder().encode(passkey),
      account: KeychainAccount.passkeyPublic,
      service: keychainService
    )
    try keychain.save(
      try JSONEncoder().encode(signedAuthorization),
      account: KeychainAccount.authorization,
      service: keychainService
    )

    return CreatedAccount(
      eoaAddress: wallet.eoaAddress,
      passkey: passkey,
      signedAuthorization: signedAuthorization
    )
  }

  public func signInWithPasskey() async throws -> SignedInAccount {
    let passkeyPublic = try storedPasskeyPublic()
    let signedAuthorization = try storedSignedAuthorization()

    _ = try await passkeyService.sign(rpId: relyingParty.rpID, payload: randomChallenge())

    let recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(signedAuthorization)
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
      return try JSONDecoder().decode(PasskeyPublicKey.self, from: data)
    } catch KeychainStoreError.dataNotFound {
      throw AccountSetupError.missingStoredPasskey
    }
  }

  public func storedSignedAuthorization() throws -> EIP7702AuthorizationSigned {
    do {
      let data = try keychain.read(account: KeychainAccount.authorization, service: keychainService)
      return try JSONDecoder().decode(EIP7702AuthorizationSigned.self, from: data)
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
