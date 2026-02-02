import Foundation

#if canImport(AccountSetup)
import AccountSetup
#if canImport(Passkey)
import Passkey
#endif
#if canImport(SignHandler)
import SignHandler
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

enum AccountSetupServiceError: Error {
    case packageNotIntegrated
    case notConfigured
    case createWalletFailed(Error)
    case signInFailed(Error)
    case restoreSessionFailed(Error)
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

    func restoreSession() async throws -> SignedInWallet {
#if canImport(AccountSetup) && canImport(SignHandler)
        guard let service else {
            throw AccountSetupServiceError.notConfigured
        }

        do {
            let passkey = try await service.storedPasskeyPublic()
            let signedAuthorization = try await service.storedSignedAuthorization()
            let recoveredAddress = try SignHandler.EIP7702AuthorizationCodec
                .recoverAuthorityAddress(signedAuthorization)

            guard recoveredAddress.caseInsensitiveCompare(passkey.userName) == .orderedSame else {
                throw AccountSetup.AccountSetupError.inconsistentStoredIdentity
            }

            return SignedInWallet(
                eoaAddress: recoveredAddress,
                passkeyCredentialID: passkey.credentialID.base64EncodedString()
            )
        } catch {
            throw AccountSetupServiceError.restoreSessionFailed(error)
        }
#else
        throw AccountSetupServiceError.packageNotIntegrated
#endif
    }
}
