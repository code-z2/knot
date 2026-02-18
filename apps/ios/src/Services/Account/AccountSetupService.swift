import AA
import AccountSetup
import Foundation
import Passkey
import RPC
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
    case passkeyVerificationFailed(Error)
}

extension AccountSetupServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .createWalletFailed(error):
            "Create account failed: \(error.localizedDescription)"
        case let .signInFailed(error):
            "Sign-in failed: \(error.localizedDescription)"
        case let .restoreSessionFailed(error):
            "Session restore failed: \(error.localizedDescription)"
        case let .knownAccountsFailed(error):
            "Loading known accounts failed: \(error.localizedDescription)"
        case let .walletMaterialLookupFailed(error):
            "Wallet material lookup failed: \(error.localizedDescription)"
        case let .passkeyLookupFailed(error):
            "Passkey lookup failed: \(error.localizedDescription)"
        case let .passkeySignFailed(error):
            "Passkey signing failed: \(error.localizedDescription)"
        case let .passkeyVerificationFailed(error):
            "Passkey verification failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class AccountSetupService {
    private let service: AccountSetup.AccountSetupService
    private let defaultDelegateAddress: String
    private let supportedChainIDs: [UInt64]
    private let rpcClient: RPCClient

    init(
        service: AccountSetup.AccountSetupService? = nil,
        delegateAddress: String = AAConstants.delegateImplementationAddress,
        supportedChainIDs: [UInt64] = ChainSupportRuntime.resolveSupportedChainIDs(),
        rpcClient: RPCClient? = nil,
    ) {
        self.service =
            service ?? AccountSetup.AccountSetupService(passkeyService: PasskeyService(anchor: nil))
        defaultDelegateAddress = delegateAddress
        self.supportedChainIDs = supportedChainIDs
        self.rpcClient = rpcClient ?? RPCClient()
    }

    func createWallet() async throws -> AccountIdentity {
        let creationChainId = supportedChainIDs.first ?? 1
        do {
            let created = try await service.createEOAAndPasskey(
                delegateAddress: defaultDelegateAddress,
                chainId: creationChainId,
                nonce: 0,
            )
            return AccountIdentity(
                eoaAddress: created.eoaAddress,
                accumulatorAddress: created.accumulatorAddress,
                passkeyCredentialID: created.passkey.credentialID,
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
        await (try? localMnemonic(for: eoaAddress)) != nil
    }

    func passkeyPublicKeyData(for account: AccountIdentity) async throws -> PasskeyPublicKey {
        do {
            return try await service.passkeyPublicKey(account: account)
        } catch {
            throw AccountSetupServiceError.passkeyLookupFailed(error)
        }
    }

    func signPayloadWithStoredPasskey(account: AccountIdentity, payload: Data) async throws -> Data {
        do {
            return try await service.signPayloadWithStoredPasskey(
                account: account,
                payload: payload,
            )
        } catch {
            throw AccountSetupServiceError.passkeySignFailed(error)
        }
    }

    func signEthMessageDigestWithStoredWallet(account: AccountIdentity, digest32: Data) async throws -> Data {
        do {
            return try await service.signEthMessageDigestWithStoredWallet(account: account, digest32: digest32)
        } catch {
            throw AccountSetupServiceError.walletMaterialLookupFailed(error)
        }
    }

    func verifyWalletBackupAccess(eoaAddress: String) async throws {
        do {
            let account = try await service.restoreStoredSession(eoaAddress: eoaAddress)
            try await service.verifyStoredPasskeyForSensitiveAction(
                account: account,
                action: "wallet-backup",
            )
        } catch {
            throw AccountSetupServiceError.passkeyVerificationFailed(error)
        }
    }

    func storedSignedAuthorization(account: AccountIdentity, chainId: UInt64) async throws
        -> EIP7702AuthorizationSigned
    {
        do {
            let nonceHex = try await rpcClient.makeRpcCall(
                chainId: chainId,
                method: "eth_getTransactionCount",
                params: [AnyCodable(account.eoaAddress), AnyCodable("pending")],
                responseType: String.self,
            )

            let cleanHex = nonceHex.replacingOccurrences(of: "0x", with: "")
            guard let nonce = UInt64(cleanHex, radix: 16) else {
                throw AccountSetupError.walletGenerationFailed(
                    NSError(
                        domain: "AccountSetupService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid nonce hex: \(nonceHex)"],
                    ),
                )
            }

            return try await service.signedAuthorization(
                account: account,
                chainId: chainId,
                delegateAddress: defaultDelegateAddress,
                nonce: nonce,
            )
        } catch {
            throw AccountSetupServiceError.restoreSessionFailed(error)
        }
    }
}
