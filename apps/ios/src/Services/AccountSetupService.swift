import Foundation

#if canImport(AccountSetup)
import AccountSetup
#if canImport(Passkey)
import Passkey
#endif
#endif

struct CreatedWallet {
    let eoaAddress: String
    let passkeyCredentialID: String
}

struct SignedInWallet {
    let eoaAddress: String
    let passkeyCredentialID: String
}

struct KnownAccount {
    let eoaAddress: String
    let passkeyCredentialID: String
}

enum AccountSetupServiceError: Error {
    case packageNotIntegrated
    case notConfigured
    case createWalletFailed(Error)
    case signInFailed(Error)
    case restoreSessionFailed(Error)
    case knownAccountsFailed(Error)
}

extension AccountSetupServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .packageNotIntegrated:
            return "Account setup package is not integrated into this app target."
        case .notConfigured:
            return "Account setup service is not configured."
        case .createWalletFailed(let error):
            return "Create account failed: \(error.localizedDescription)"
        case .signInFailed(let error):
            return "Sign-in failed: \(error.localizedDescription)"
        case .restoreSessionFailed(let error):
            return "Session restore failed: \(error.localizedDescription)"
        case .knownAccountsFailed(let error):
            return "Loading known accounts failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class AccountSetupService {
#if canImport(AccountSetup)
    private let service: AccountSetup.AccountSetupService?
    private let defaultDelegateAddress: String
    private let defaultChainID: UInt64

    init(
        service: AccountSetup.AccountSetupService? = nil,
        delegateAddress: String = "0x0000000000000000000000000000000000000001",
        chainID: UInt64 = 1
    ) {
#if canImport(Passkey)
        self.service = service ?? AccountSetup.AccountSetupService(
            passkeyService: PasskeyService(anchor: nil)
        )
#else
        self.service = service
#endif
        self.defaultDelegateAddress = delegateAddress
        self.defaultChainID = chainID
    }
#else
    init() {}
#endif

    func createWallet() async throws -> CreatedWallet {
#if canImport(AccountSetup)
        guard let service else {
            throw AccountSetupServiceError.notConfigured
        }

        let created: AccountSetup.CreatedAccount
        do {
            created = try await service.createEOAAndPasskey(
                delegateAddress: defaultDelegateAddress,
                chainId: defaultChainID,
                nonce: 0
            )
        } catch {
            throw AccountSetupServiceError.createWalletFailed(error)
        }
        return CreatedWallet(
            eoaAddress: created.eoaAddress,
            passkeyCredentialID: created.passkey.credentialID.base64EncodedString()
        )
#else
        throw AccountSetupServiceError.packageNotIntegrated
#endif
    }

    func signIn() async throws -> SignedInWallet {
#if canImport(AccountSetup)
        guard let service else {
            throw AccountSetupServiceError.notConfigured
        }

        let signedIn: AccountSetup.SignedInAccount
        do {
            signedIn = try await service.signInWithPasskey()
        } catch {
            throw AccountSetupServiceError.signInFailed(error)
        }
        return SignedInWallet(
            eoaAddress: signedIn.eoaAddress,
            passkeyCredentialID: signedIn.passkeyCredentialID.base64EncodedString()
        )
#else
        throw AccountSetupServiceError.packageNotIntegrated
#endif
    }

    func restoreSession(eoaAddress: String) async throws -> SignedInWallet {
#if canImport(AccountSetup)
        guard let service else {
            throw AccountSetupServiceError.notConfigured
        }

        do {
            let restored = try await service.restoreStoredSession(eoaAddress: eoaAddress)
            return SignedInWallet(
                eoaAddress: restored.eoaAddress,
                passkeyCredentialID: restored.passkeyCredentialID.base64EncodedString()
            )
        } catch {
            throw AccountSetupServiceError.restoreSessionFailed(error)
        }
#else
        throw AccountSetupServiceError.packageNotIntegrated
#endif
    }

    func knownAccounts() async throws -> [KnownAccount] {
#if canImport(AccountSetup)
        guard let service else {
            throw AccountSetupServiceError.notConfigured
        }

        do {
            return try await service.storedAccounts().map {
                KnownAccount(
                    eoaAddress: $0.eoaAddress,
                    passkeyCredentialID: $0.passkeyCredentialID.base64EncodedString()
                )
            }
        } catch {
            throw AccountSetupServiceError.knownAccountsFailed(error)
        }
#else
        throw AccountSetupServiceError.packageNotIntegrated
#endif
    }
}
