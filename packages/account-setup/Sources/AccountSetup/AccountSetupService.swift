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

public struct AccountIdentity: Equatable, Sendable {
  public let eoaAddress: String
  public let passkeyCredentialID: Data

  public init(eoaAddress: String, passkeyCredentialID: Data) {
    self.eoaAddress = eoaAddress
    self.passkeyCredentialID = passkeyCredentialID
  }
}

public enum AccountSetupError: Error {
  case missingStoredPasskey
  case walletGenerationFailed(Error)
  case passkeyRegistrationFailed(Error)
  case authorizationSigningFailed(Error)
  case walletStorageFailed(Error)
  case authorizationStorageFailed(Error)
  case passkeyAssertionFailed(Error)
  case authorizationRecoveryFailed(Error)
  case authorizationDecodeFailed(Error)
  case missingStoredAccount(String)
}

extension AccountSetupError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingStoredPasskey:
      return "No stored passkey public data found."
    case .walletGenerationFailed(let error):
      return "Failed to generate wallet material: \(error.localizedDescription)"
    case .passkeyRegistrationFailed(let error):
      return "Passkey registration failed: \(error.localizedDescription)"
    case .authorizationSigningFailed(let error):
      return "Failed to sign EIP-7702 authorization: \(error.localizedDescription)"
    case .walletStorageFailed(let error):
      return "Failed to persist wallet material locally: \(error.localizedDescription)"
    case .authorizationStorageFailed(let error):
      return "Failed to save signed authorization: \(error.localizedDescription)"
    case .passkeyAssertionFailed(let error):
      return "Passkey assertion failed during sign-in: \(error.localizedDescription)"
    case .authorizationRecoveryFailed(let error):
      return "Failed to recover signer from signed authorization: \(error.localizedDescription)"
    case .authorizationDecodeFailed(let error):
      return "Stored authorization data could not be decoded: \(error.localizedDescription)"
    case .missingStoredAccount(let eoaAddress):
      return "No stored account found for EOA \(eoaAddress)."
    }
  }
}

public protocol WalletMaterialStoring {
  func save(_ wallet: WalletMaterial, for eoaAddress: String) throws
  func read(for eoaAddress: String) throws -> WalletMaterial
  func readAll() throws -> [String: WalletMaterial]
}

public struct LocalWalletMaterialStore: WalletMaterialStoring {
  private let fileURL: URL

  public init(filename: String = "wallet-materials.json") {
    let baseDirectory =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.fileURL = baseDirectory.appendingPathComponent(filename)
  }

  public func save(_ wallet: WalletMaterial, for eoaAddress: String) throws {
    let key = Self.normalizedAddressKey(eoaAddress)
    var all = (try? readAll()) ?? [:]
    all[key] = wallet
    let data = try JSONEncoder().encode(all)
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    try data.write(to: fileURL, options: .atomic)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var writableURL = fileURL
    try? writableURL.setResourceValues(resourceValues)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: fileURL.path
    )
  }

  public func read(for eoaAddress: String) throws -> WalletMaterial {
    let key = Self.normalizedAddressKey(eoaAddress)
    let all = try readAll()
    guard let wallet = all[key] else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return wallet
  }

  public func readAll() throws -> [String: WalletMaterial] {
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([String: WalletMaterial].self, from: data)
  }

  private static func normalizedAddressKey(_ eoaAddress: String) -> String {
    eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

public actor AccountSetupService {
  private enum KeychainAccount {
    static let accounts = "accounts.v1"
  }

  private struct StoredAccountRecord: Codable, Equatable, Sendable {
    let passkey: PasskeyPublicKey
    let signedAuthorization: EIP7702AuthorizationSigned
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
      try walletStore.save(wallet, for: wallet.eoaAddress)
    } catch {
      throw AccountSetupError.walletStorageFailed(error)
    }

    do {
      var accounts = try loadStoredAccountRecords()
      upsertStoredAccount(
        &accounts,
        record: StoredAccountRecord(
          passkey: passkey,
          signedAuthorization: signedAuthorization
        )
      )
      try persistStoredAccountRecords(accounts)
    } catch {
      throw AccountSetupError.authorizationStorageFailed(error)
    }

    return CreatedAccount(
      eoaAddress: wallet.eoaAddress,
      passkey: passkey,
      signedAuthorization: signedAuthorization
    )
  }

  public func signInWithPasskey() async throws -> AccountIdentity {
    let storedAccounts = try loadStoredAccountRecords()
    guard !storedAccounts.isEmpty else {
      throw AccountSetupError.missingStoredPasskey
    }
    let allowedCredentialIDs = storedAccounts.map { $0.passkey.credentialID }

    let signature: PasskeySignature

    do {
      signature = try await passkeyService.sign(
        rpId: relyingParty.rpID,
        payload: randomChallenge(),
        allowedCredentialIDs: allowedCredentialIDs
      )
    } catch {
      throw AccountSetupError.passkeyAssertionFailed(error)
    }

    guard
      let matched = storedAccounts.first(where: {
        $0.passkey.credentialID == signature.credentialID
      })
    else {
      throw AccountSetupError.missingStoredPasskey
    }

    let recoveredAddress: String
    do {
      recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
        matched.signedAuthorization
      )
    } catch {
      throw AccountSetupError.authorizationRecoveryFailed(error)
    }
    return AccountIdentity(
      eoaAddress: recoveredAddress,
      passkeyCredentialID: matched.passkey.credentialID
    )
  }

  public func storedWalletMaterial(eoaAddress: String) throws -> WalletMaterial {
    try walletStore.read(for: eoaAddress)
  }

  public func storedWalletMaterials() throws -> [String: WalletMaterial] {
    (try? walletStore.readAll()) ?? [:]
  }

  public func storedAccounts() throws -> [AccountIdentity] {
    try loadStoredAccountRecords().map { record in
      let recoveredAddress: String
      do {
        recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
          record.signedAuthorization
        )
      } catch {
        throw AccountSetupError.authorizationRecoveryFailed(error)
      }
      return AccountIdentity(
        eoaAddress: recoveredAddress,
        passkeyCredentialID: record.passkey.credentialID
      )
    }
  }

  public func restoreStoredSession(eoaAddress: String) throws -> AccountIdentity {
    let normalized = normalizedAddressKey(eoaAddress)
    let records = try loadStoredAccountRecords()

    for record in records {
      let recoveredAddress: String
      do {
        recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
          record.signedAuthorization
        )
      } catch {
        throw AccountSetupError.authorizationRecoveryFailed(error)
      }

      if normalizedAddressKey(recoveredAddress) == normalized {
        return AccountIdentity(
          eoaAddress: recoveredAddress,
          passkeyCredentialID: record.passkey.credentialID
        )
      }
    }

    throw AccountSetupError.missingStoredAccount(eoaAddress)
  }

  public func signPayloadWithStoredPasskey(
    account: AccountIdentity,
    payload: Data
  ) async throws -> Data {
    let passkey = try passkeyPublicKey(account: account)
    let signature: PasskeySignature
    do {
      signature = try await passkeyService.sign(
        rpId: relyingParty.rpID,
        payload: payload,
        allowedCredentialIDs: [passkey.credentialID]
      )
    } catch {
      throw AccountSetupError.passkeyAssertionFailed(error)
    }

    do {
      return try signature.webAuthnAuthBytes(payload: payload)
    } catch {
      throw AccountSetupError.passkeyAssertionFailed(error)
    }
  }

  public func passkeyPublicKey(account: AccountIdentity) throws -> PasskeyPublicKey {
    let records = try loadStoredAccountRecords()
    if let matched = records.first(where: { $0.passkey.credentialID == account.passkeyCredentialID }
    ) {
      return matched.passkey
    }
    throw AccountSetupError.missingStoredAccount(account.eoaAddress)
  }

  public func signedAuthorization(
    account: AccountIdentity,
    chainId: UInt64,
    delegateAddress: String,
    nonce: UInt64 = 0
  ) throws -> EIP7702AuthorizationSigned {
    let records = try loadStoredAccountRecords()
    guard
      let matched = records.first(where: {
        $0.passkey.credentialID == account.passkeyCredentialID
      })
    else {
      throw AccountSetupError.missingStoredAccount(account.eoaAddress)
    }

    if matched.signedAuthorization.chainId == chainId {
      return matched.signedAuthorization
    }

    // JIT Signing
    let wallet = try walletStore.read(for: account.eoaAddress)
    let unsigned = EIP7702AuthorizationUnsigned(
      chainId: chainId,
      delegateAddress: delegateAddress,
      nonce: nonce
    )
    return try EIP7702AuthorizationCodec.signAuthorization(
      unsigned,
      privateKeyHex: wallet.privateKeyHex
    )
  }

  private func randomChallenge(length: Int = 32) -> Data {
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
  }

  private func loadStoredAccountRecords() throws -> [StoredAccountRecord] {
    do {
      let data = try keychain.read(account: KeychainAccount.accounts, service: keychainService)
      return try JSONDecoder().decode([StoredAccountRecord].self, from: data)
    } catch KeychainStoreError.dataNotFound {
      return []
    } catch let decodingError as DecodingError {
      throw AccountSetupError.authorizationDecodeFailed(decodingError)
    } catch {
      throw error
    }
  }

  private func persistStoredAccountRecords(_ records: [StoredAccountRecord]) throws {
    try keychain.save(
      try JSONEncoder().encode(records),
      account: KeychainAccount.accounts,
      service: keychainService
    )
  }

  private func upsertStoredAccount(
    _ records: inout [StoredAccountRecord],
    record: StoredAccountRecord
  ) {
    if let credentialIndex = records.firstIndex(where: {
      $0.passkey.credentialID == record.passkey.credentialID
    }) {
      records[credentialIndex] = record
      return
    }
    if let addressIndex = records.firstIndex(where: { existing in
      let lhs = try? EIP7702AuthorizationCodec.recoverAuthorityAddress(existing.signedAuthorization)
      let rhs = try? EIP7702AuthorizationCodec.recoverAuthorityAddress(record.signedAuthorization)
      guard let lhs, let rhs else { return false }
      return normalizedAddressKey(lhs) == normalizedAddressKey(rhs)
    }) {
      records[addressIndex] = record
      return
    }
    records.append(record)
  }

  private func normalizedAddressKey(_ eoaAddress: String) -> String {
    eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
