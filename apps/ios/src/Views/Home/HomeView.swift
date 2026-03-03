// HomeView.swift
// Created by Peter Anyaogu on 03/03/2026.

import Balance
import SwiftUI

struct HomeView: View {
    let balanceStore: BalanceStore
    let preferencesStore: PreferencesStore
    let currencyRateStore: CurrencyRateStore
    let onSignOut: () -> Void
    let onAddMoney: () -> Void
    let onSendMoney: () -> Void
    let onProfileTap: () -> Void
    let onPreferencesTap: () -> Void
    let onWalletBackupTap: () -> Void
    let onAddressBookTap: () -> Void
    let onRefreshWallet: () async -> Void
    let onCheckForUpdates: () async -> StoredSingletonConfig?
    let onPerformUpdate: (StoredSingletonConfig) async -> Bool
    let showWalletBackup: Bool

    init(
        balanceStore: BalanceStore,
        preferencesStore: PreferencesStore,
        currencyRateStore: CurrencyRateStore,
        onSignOut: @escaping () -> Void,
        onAddMoney: @escaping () -> Void = {},
        onSendMoney: @escaping () -> Void = {},
        onProfileTap: @escaping () -> Void = {},
        onPreferencesTap: @escaping () -> Void = {},
        onWalletBackupTap: @escaping () -> Void = {},
        onAddressBookTap: @escaping () -> Void = {},
        onRefreshWallet: @escaping () async -> Void = {},
        onCheckForUpdates: @escaping () async -> StoredSingletonConfig? = { nil },
        onPerformUpdate: @escaping (StoredSingletonConfig) async -> Bool = { _ in false },
        showWalletBackup: Bool = true,
    ) {
        self.balanceStore = balanceStore
        self.preferencesStore = preferencesStore
        self.currencyRateStore = currencyRateStore
        self.onSignOut = onSignOut
        self.onAddMoney = onAddMoney
        self.onSendMoney = onSendMoney
        self.onProfileTap = onProfileTap
        self.onPreferencesTap = onPreferencesTap
        self.onWalletBackupTap = onWalletBackupTap
        self.onAddressBookTap = onAddressBookTap
        self.onRefreshWallet = onRefreshWallet
        self.onCheckForUpdates = onCheckForUpdates
        self.onPerformUpdate = onPerformUpdate
        self.showWalletBackup = showWalletBackup
    }

    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("home_title")
                    .font(AppTypography.homeTitle)
                    .foregroundStyle(AppThemeColor.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xxl)

                HomeBalanceSectionView(
                    accountBalanceDisplay: accountBalanceDisplay,
                    isBalanceHidden: Binding(
                        get: { preferencesStore.isBalanceHidden },
                        set: { preferencesStore.isBalanceHidden = $0 }
                    ),
                    onAddMoney: { handleAddMoneyTap() },
                    onSendMoney: { handleSendMoneyTap() },
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)

                Rectangle()
                    .foregroundColor(.clear)
                    .frame(height: 4)
                    .background(AppThemeColor.separatorOpaque)

                if updateBannerPhase != .hidden, let pendingSingletonConfig {
                    AccountUpdateBannerView(
                        phase: $updateBannerPhase,
                        version: pendingSingletonConfig.version,
                        releaseNotes: nil,
                        onUpdateTap: { performUpdate() },
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: updateBannerPhase)
                }

                HomeSettingsListView(
                    assetsSummaryLabel: assetsSummaryLabel,
                    showWalletBackup: showWalletBackup,
                    isLoggingOut: isLoggingOut,
                    isCheckingForUpdates: isCheckingForUpdates,
                    onPresentAssets: { presentAssetsModal() },
                    onProfileTap: { handleProfileTap() },
                    onPreferencesTap: { handlePreferencesTap() },
                    onWalletBackupTap: { handleWalletBackupTap() },
                    onAddressBookTap: { handleAddressBookTap() },
                    onCheckForUpdates: { checkForUpdates() },
                    onBeginLogout: { beginLogout() },
                    onRefresh: { await refreshBalances() },
                )
            }
            .safeAreaPadding(.top, AppSpacing.sm)
        }
        .sheet(item: $activeModal) { modal in
            AppSheet(kind: modal.sheetKind) {
                modalContent(for: modal)
            }
        }
        .sensoryFeedback(AppHaptic.lightImpact.sensoryFeedback, trigger: lightImpactTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
        .sensoryFeedback(AppHaptic.warning.sensoryFeedback, trigger: warningTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
        .sensoryFeedback(AppHaptic.mediumImpact.sensoryFeedback, trigger: refreshTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
        .onDisappear {
            logoutTask?.cancel()
            logoutTask = nil
        }
    }

    @State var activeModal: HomeModal?
    @State private var assetSearchText = ""
    @State var isLoggingOut = false
    @State var logoutTask: Task<Void, Never>?
    @State var updateBannerPhase: UpdateBannerPhase = .hidden
    @State private var pendingSingletonConfig: StoredSingletonConfig?
    @State var isCheckingForUpdates = false
    // Haptic triggers
    @State var lightImpactTrigger = 0
    @State var selectionTrigger = 0
    @State var warningTrigger = 0
    @State var refreshTrigger = 0

    private var assetListState: AssetListState {
        balanceStore.isLoading ? .loading : .loaded(balanceStore.balances)
    }

    private var accountBalanceDisplay: String {
        currencyRateStore.formatUSD(
            balanceStore.totalValueUSD,
            currencyCode: preferencesStore.selectedCurrencyCode,
            locale: preferencesStore.locale,
        )
    }

    private var assetsSummaryLabel: Text {
        let assetCount = balanceStore.balances.count
        let chainCount: Int
        if !balanceStore.activeChainIDs.isEmpty {
            chainCount = balanceStore.activeChainIDs.count
        } else {
            // Fallback: derive from balance data
            let uniqueChains = Set(balanceStore.balances.flatMap { $0.chainBalances.map(\.chainID) })
            chainCount = uniqueChains.count
        }

        guard assetCount > 0 else { return Text("home_assets_summary_empty") }
        return Text("home_assets_summary_dynamic \(assetCount) \(chainCount)")
    }

    private func performUpdate() {
        guard updateBannerPhase == .available else { return }

        Task { @MainActor in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                updateBannerPhase = .inProgress
            }

            // Slight artificial delay for perceived weight.
            try? await Task.sleep(for: .milliseconds(900))

            guard let pendingConfig = pendingSingletonConfig else {
                updateBannerPhase = .hidden
                return
            }

            let success = await onPerformUpdate(pendingConfig)

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                updateBannerPhase = success ? .complete : .hidden
            }

            if success {
                pendingSingletonConfig = nil
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    updateBannerPhase = .hidden
                }
            }
        }
    }

    private func checkForUpdates() {
        guard !isCheckingForUpdates else { return }

        Task { @MainActor in
            isCheckingForUpdates = true
            defer { isCheckingForUpdates = false }

            if let result = await onCheckForUpdates() {
                pendingSingletonConfig = result
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    updateBannerPhase = .available
                }
            } else {
                pendingSingletonConfig = nil
            }
        }
    }

    @ViewBuilder
    private func modalContent(for modal: HomeModal) -> some View {
        switch modal {
        case .assets:
            AssetsListModal(
                query: $assetSearchText,
                state: assetListState,
                displayCurrencyCode: preferencesStore.selectedCurrencyCode,
                displayLocale: preferencesStore.locale,
                usdToSelectedRate: currencyRateStore.rateFromUSD(to: preferencesStore.selectedCurrencyCode),
            )
        }
    }
}

#Preview {
    HomeView(
        balanceStore: BalanceStore(),
        preferencesStore: PreferencesStore(),
        currencyRateStore: CurrencyRateStore(),
        onSignOut: {},
    )
    .preferredColorScheme(.dark)
}
