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
    private let sessionStore: SessionStore
    private let faucetService: FaucetService

    init(
        accountService: AccountSetupService? = nil,
        sessionStore: SessionStore? = nil,
        faucetService: FaucetService? = nil,
    ) {
        self.accountService = accountService ?? AccountSetupService()
        self.sessionStore = sessionStore ?? SessionStore()
        self.faucetService = faucetService ?? FaucetService()
    }

    func bootstrap() async -> AppBootstrapResultModel {
        guard let activeEOA = sessionStore.activeEOAAddress else {
            return .onboarding
        }

        let restored: AccountSession
        do {
            restored = try await accountService.restoreSession(eoaAddress: activeEOA)
        } catch {
            print("❌ [AppSessionFlowService] bootstrap restore failed: \(error.localizedDescription)")
            sessionStore.clearActiveSession()
            return .onboarding
        }

        let hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(
            for: restored.eoaAddress,
        )
        return .activeSession(
            AppSessionStateModel(
                eoaAddress: restored.eoaAddress,
                accumulatorAddress: restored.accumulatorAddress,
                hasLocalWalletMaterial: hasLocalWalletMaterial,
            ),
        )
    }

    func createWallet() async -> AppSessionStateModel? {
        let restored: AccountSession
        do {
            restored = try await accountService.createWallet()
        } catch {
            print("❌ [AppSessionFlowService] createWallet failed: \(error.localizedDescription)")
            return nil
        }

        sessionStore.setActiveSession(eoaAddress: restored.eoaAddress)
        let hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(
            for: restored.eoaAddress,
        )
        return AppSessionStateModel(
            eoaAddress: restored.eoaAddress,
            accumulatorAddress: restored.accumulatorAddress,
            hasLocalWalletMaterial: hasLocalWalletMaterial,
        )
    }

    func signIn() async -> AppSessionStateModel? {
        let restored: AccountSession
        do {
            restored = try await accountService.signIn()
        } catch {
            print("❌ [AppSessionFlowService] signIn failed: \(error.localizedDescription)")
            return nil
        }

        sessionStore.setActiveSession(eoaAddress: restored.eoaAddress)
        let hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(
            for: restored.eoaAddress,
        )
        return AppSessionStateModel(
            eoaAddress: restored.eoaAddress,
            accumulatorAddress: restored.accumulatorAddress,
            hasLocalWalletMaterial: hasLocalWalletMaterial,
        )
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
        guard await (try? accountService.verifyWalletBackupAccess(eoaAddress: eoaAddress)) != nil else {
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
