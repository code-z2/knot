// AppSessionFlowService.swift
// Created by Peter Anyaogu on 03/03/2026.

import AA
import AccountSetup
import Foundation
import RPC

@MainActor
final class AppSessionFlowService {
    let accountService: AccountSetupService
    let biometricAuth: BiometricAuthService
    private let sessionStore: SessionStore
    private let faucetService: FaucetService
    private let singletonConfigStore: SingletonConfigStore
    private let singletonVersionService: SingletonVersionService

    init(
        accountService: AccountSetupService? = nil,
        sessionStore: SessionStore? = nil,
        faucetService: FaucetService? = nil,
        biometricAuth: BiometricAuthService? = nil,
        singletonConfigStore: SingletonConfigStore? = nil,
        singletonVersionService: SingletonVersionService? = nil,
    ) {
        self.accountService = accountService ?? AccountSetupService()
        self.sessionStore = sessionStore ?? SessionStore()
        self.faucetService = faucetService ?? FaucetService()
        self.biometricAuth = biometricAuth ?? BiometricAuthService()
        self.singletonConfigStore = singletonConfigStore ?? SingletonConfigStore()
        self.singletonVersionService = singletonVersionService ?? SingletonVersionService()
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
        let mode = ChainSupportRuntime.resolveMode()
        guard let latestConfig = await singletonVersionService.fetchLatest(mode: mode) else {
            print("❌ [AppSessionFlowService] createWallet failed: missing singleton config")
            return nil
        }

        do {
            let created = try await accountService.createWallet(
                delegateAddress: latestConfig.delegateAddress,
                accumulatorFactoryAddress: latestConfig.accumulatorFactory,
            )
            sessionStore.setActiveSession(eoaAddress: created.eoaAddress)
            let hasWallet = await accountService.hasLocalWalletMaterial(for: created.eoaAddress)

            do {
                try singletonConfigStore.save(latestConfig, for: created.eoaAddress, mode: mode)
            } catch {
                print(
                    "❌ [AppSessionFlowService] createWallet failed: keychain save error: \(error.localizedDescription)",
                )
                return nil
            }

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

    func checkForSingletonUpdate(eoaAddress: String, mode: ChainSupportMode) async
        -> StoredSingletonConfig?
    {
        guard let latestConfig = await singletonVersionService.fetchLatest(mode: mode) else {
            return nil
        }
        guard let currentConfig = singletonConfigStore.read(for: eoaAddress, mode: mode) else {
            return latestConfig
        }
        return currentConfig.version == latestConfig.version ? nil : latestConfig
    }

    func performSingletonUpdate(
        eoaAddress: String,
        config: StoredSingletonConfig,
        mode: ChainSupportMode,
    ) async -> String? {
        do {
            let accumulatorAddress = try await accountService.updateAccumulatorAddress(
                for: eoaAddress,
                accumulatorFactoryAddress: config.accumulatorFactory,
            )
            try singletonConfigStore.save(config, for: eoaAddress, mode: mode)
            return accumulatorAddress
        } catch {
            print("❌ [AppSessionFlowService] update failed: \(error.localizedDescription)")
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
            try await biometricAuth.authenticate(
                reason: String(localized: "biometric_reason_wallet_backup"),
            )
        } catch {
            return nil
        }
        return try? await accountService.localMnemonic(for: eoaAddress)
    }

    func triggerFaucetIfNeeded(walletAddress: String, mode: ChainSupportMode) async {
        guard mode == .testnet else { return }
        await faucetService.fundAccount(eoaAddress: walletAddress, mode: mode)
    }
}
