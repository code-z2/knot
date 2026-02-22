import AccountSetup
import Foundation
import RPC

struct AppSessionStateModel: Sendable {
    let eoaAddress: String
    let accumulatorAddress: String
    let hasLocalWalletMaterial: Bool
}

enum AppBootstrapResultModel: Sendable {
    case onboarding
    case activeSession(AppSessionStateModel)
}

@MainActor
final class AppSessionFlowService {
    let accountService: AccountSetupService
    let biometricAuth: BiometricAuthService
    private let sessionStore: SessionStore
    private let faucetService: FaucetService

    init(
        accountService: AccountSetupService? = nil,
        sessionStore: SessionStore? = nil,
        faucetService: FaucetService? = nil,
        biometricAuth: BiometricAuthService? = nil,
    ) {
        self.accountService = accountService ?? AccountSetupService()
        self.sessionStore = sessionStore ?? SessionStore()
        self.faucetService = faucetService ?? FaucetService()
        self.biometricAuth = biometricAuth ?? BiometricAuthService()
    }

    func bootstrap() async -> AppBootstrapResultModel {
        guard let activeEOA = sessionStore.activeEOAAddress else {
            return .onboarding
        }

        do {
            let restored = try await accountService.restoreSession(eoaAddress: activeEOA)
            let hasWallet = await accountService.hasLocalWalletMaterial(for: restored.eoaAddress)
            return .activeSession(
                AppSessionStateModel(
                    eoaAddress: restored.eoaAddress,
                    accumulatorAddress: restored.accumulatorAddress,
                    hasLocalWalletMaterial: hasWallet,
                ),
            )
        } catch {
            print("❌ [AppSessionFlowService] bootstrap restore failed: \(error.localizedDescription)")
            sessionStore.clearActiveSession()
            return .onboarding
        }
    }

    func createWallet() async -> AppSessionStateModel? {
        do {
            let created = try await accountService.createWallet()
            sessionStore.setActiveSession(eoaAddress: created.eoaAddress)
            let hasWallet = await accountService.hasLocalWalletMaterial(for: created.eoaAddress)
            return AppSessionStateModel(
                eoaAddress: created.eoaAddress,
                accumulatorAddress: created.accumulatorAddress,
                hasLocalWalletMaterial: hasWallet,
            )
        } catch {
            print("❌ [AppSessionFlowService] createWallet failed: \(error.localizedDescription)")
            return nil
        }
    }

    func signIn() async -> AppSessionStateModel? {
        do {
            let restored = try await accountService.signIn()
            sessionStore.setActiveSession(eoaAddress: restored.eoaAddress)
            let hasWallet = await accountService.hasLocalWalletMaterial(for: restored.eoaAddress)
            return AppSessionStateModel(
                eoaAddress: restored.eoaAddress,
                accumulatorAddress: restored.accumulatorAddress,
                hasLocalWalletMaterial: hasWallet,
            )
        } catch {
            print("❌ [AppSessionFlowService] signIn failed: \(error.localizedDescription)")
            return nil
        }
    }

    func signOut() {
        sessionStore.clearActiveSession()
    }

    func backupMnemonicIfAvailable(
        eoaAddress: String?,
        hasLocalWalletMaterial: Bool,
    ) async -> String? {
        guard let eoaAddress else { return nil }
        guard hasLocalWalletMaterial else { return nil }
        do {
            try await biometricAuth.authenticate(reason: "Authenticate to reveal your recovery phrase")
        } catch {
            return nil
        }
        return try? await accountService.localMnemonic(for: eoaAddress)
    }

    func resolveAccumulatorAddress(
        eoaAddress: String?,
        fallbackAccumulatorAddress: String?,
    ) async -> String? {
        if let fallbackAccumulatorAddress {
            return fallbackAccumulatorAddress
        }

        guard let eoaAddress else {
            return nil
        }

        guard let restored = try? await accountService.restoreSession(eoaAddress: eoaAddress) else {
            return nil
        }

        return restored.accumulatorAddress
    }

    func triggerFaucetIfNeeded(walletAddress: String, mode: ChainSupportMode) async {
        guard mode == .limitedTestnet else { return }
        await faucetService.fundAccount(eoaAddress: walletAddress, mode: mode)
    }
}
