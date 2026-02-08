import AccountSetup
import Foundation
import Passkey
internal import SignHandler

typealias AccountIdentity = AccountSetup.AccountIdentity

enum AccountSetupServiceError: Error {
  case createWalletFailed(Error)
  case signInFailed(Error)
  case restoreSessionFailed(Error)
  case knownAccountsFailed(Error)
  case walletMaterialLookupFailed(Error)
  case passkeyLookupFailed(Error)
  case passkeySignFailed(Error)
}

extension AccountSetupServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .createWalletFailed(let error):
      return "Create account failed: \(error.localizedDescription)"
    case .signInFailed(let error):
      return "Sign-in failed: \(error.localizedDescription)"
    case .restoreSessionFailed(let error):
      return "Session restore failed: \(error.localizedDescription)"
    case .knownAccountsFailed(let error):
      return "Loading known accounts failed: \(error.localizedDescription)"
    case .walletMaterialLookupFailed(let error):
      return "Wallet material lookup failed: \(error.localizedDescription)"
    case .passkeyLookupFailed(let error):
      return "Passkey lookup failed: \(error.localizedDescription)"
    case .passkeySignFailed(let error):
      return "Passkey signing failed: \(error.localizedDescription)"
    }
  }
}

@MainActor
final class AccountSetupService {
  private let service: AccountSetup.AccountSetupService
  private let defaultDelegateAddress: String
  private let defaultChainID: UInt64

  init(
    service: AccountSetup.AccountSetupService? = nil,
    delegateAddress: String = "0x919FB6f181DC306825Dc8F570A1BDF8c456c56Da",
    chainID: UInt64 = 1
  ) {
    self.service =
      service ?? AccountSetup.AccountSetupService(passkeyService: PasskeyService(anchor: nil))
    self.defaultDelegateAddress = delegateAddress
    self.defaultChainID = chainID
  }

  func createWallet() async throws -> AccountIdentity {
    do {
      let created = try await service.createEOAAndPasskey(
        delegateAddress: defaultDelegateAddress,
        chainId: defaultChainID,
        nonce: 0
      )
      return AccountIdentity(
        eoaAddress: created.eoaAddress,
        passkeyCredentialID: created.passkey.credentialID
      )
    } catch {
      throw AccountSetupServiceError.createWalletFailed(error)
    }
  }

  func signIn() async throws -> AccountIdentity {
    do {
      return try await service.signInWithPasskey()
    } catch {
      throw AccountSetupServiceError.signInFailed(error)
    }
  }

  func restoreSession(eoaAddress: String) async throws -> AccountIdentity {
    do {
      return try await service.restoreStoredSession(eoaAddress: eoaAddress)
    } catch {
      throw AccountSetupServiceError.restoreSessionFailed(error)
    }
  }

  func restoreSession(account: AccountIdentity) async throws -> AccountIdentity {
    do {
      let passkey = try await service.passkeyPublicKey(account: account)
      let stored = try await service.storedAccounts()
      if let match = stored.first(where: {
        $0.passkeyCredentialID == passkey.credentialID
      }) {
        return match
      }
      throw AccountSetupError.missingStoredAccount(account.eoaAddress)
    } catch {
      throw AccountSetupServiceError.restoreSessionFailed(error)
    }
  }

  func knownAccounts() async throws -> [AccountIdentity] {
    do {
      return try await service.storedAccounts()
    } catch {
      throw AccountSetupServiceError.knownAccountsFailed(error)
    }
  }

  func localMnemonic(for eoaAddress: String) async throws -> String {
    do {
      return try await service.storedWalletMaterial(eoaAddress: eoaAddress).mnemonic
    } catch {
      throw AccountSetupServiceError.walletMaterialLookupFailed(error)
    }
  }

  func hasLocalWalletMaterial(for eoaAddress: String) async -> Bool {
    (try? await localMnemonic(for: eoaAddress)) != nil
  }

  func passkeyPublicKeyData(for account: AccountIdentity) async throws -> PasskeyPublicKey {
    do {
      let passkey = try await service.passkeyPublicKey(account: account)
      return passkey
    } catch {
      throw AccountSetupServiceError.passkeyLookupFailed(error)
    }
  }

  func signPayloadWithStoredPasskey(account: AccountIdentity, payload: Data) async throws -> Data {
    do {
      return try await service.signPayloadWithStoredPasskey(
        account: account,
        payload: payload
      )
    } catch {
      throw AccountSetupServiceError.passkeySignFailed(error)
    }
  }

  func storedSignedAuthorization(account: AccountIdentity) async throws
    -> EIP7702AuthorizationSigned
  {
    do {
      return try await service.signedAuthorization(account: account)
    } catch {
      throw AccountSetupServiceError.restoreSessionFailed(error)
    }
  }
}
