import RPC
import SwiftUI

struct GasTankInformationView: View {
    let preferencesStore: PreferencesStore
    let feeAbstractionStore: FeeAbstractionStore
    let onWithdrawAllFunds: (() -> Void)?

    @State private var selectionTrigger = 0
    @State private var pendingConfirmation: TransactionConfirmationModel?
    @State private var withdrawActionState: AppButtonVisualState = .normal
    @State private var withdrawTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    GasTankInformationCardView(
                        supportedChains: supportedChains,
                        withdrawActionState: withdrawActionState,
                        onWithdrawTap: presentWithdrawConfirmation,
                    )

                    Text("gas_tank_information_withdraw_info")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppThemeColor.labelSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 357)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.xxxl + AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .appNavigation(
            titleKey: "",
            displayMode: .inline,
            hidesBackButton: false,
        )
        .appNavigationScrollEdgeStyle()
        .sheet(item: $pendingConfirmation) { model in
            TransactionConfirmationSheet(model: model)
        }
        .onDisappear {
            withdrawTask?.cancel()
            withdrawTask = nil
        }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
    }

    private var supportedChains: [GasTankInformationChainItem] {
        [
            chainItem(chainID: 1),
            chainItem(chainID: 8_453),
            chainItem(chainID: 42_161),
            chainItem(chainID: 143),
            chainItem(chainID: 10),
            chainItem(chainID: 130),
            chainItem(chainID: 137),
            chainItem(chainID: 56, titleOverride: "Binance"),
            chainItem(chainID: 324),
            GasTankInformationChainItem(
                id: "others",
                title: String(localized: "gas_tank_information_supported_chains_other"),
            ),
        ]
    }

    private func presentWithdrawConfirmation() {
        guard withdrawActionState != .loading else { return }
        selectionTrigger += 1
        pendingConfirmation = withdrawConfirmationModel()
    }

    private func confirmWithdraw(actionId: UUID) {
        guard let onWithdrawAllFunds else { return }

        updatePendingConfirmationAction(
            actionId: actionId,
            visualState: .loading,
            isEnabled: false,
        )

        withdrawActionState = .loading
        withdrawTask?.cancel()
        withdrawTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(0.9))
            } catch {
                withdrawActionState = .normal
                pendingConfirmation = nil
                return
            }

            onWithdrawAllFunds()
            updatePendingConfirmationAction(
                actionId: actionId,
                visualState: .success,
                isEnabled: false,
            )
            withdrawActionState = .success

            try? await Task.sleep(for: .seconds(0.8))
            pendingConfirmation = nil
            withdrawActionState = .normal
        }
    }

    private func updatePendingConfirmationAction(
        actionId: UUID,
        visualState: AppButtonVisualState,
        isEnabled: Bool,
    ) {
        guard let pendingConfirmation else { return }
        self.pendingConfirmation = pendingConfirmation.updatingAction(
            id: actionId,
            visualState: visualState,
            isEnabled: isEnabled,
            disableOthers: true,
        )
    }

    private var withdrawBlockReason: LocalizedStringKey? {
        guard let balanceNative = feeAbstractionStore.balanceNative else {
            return "gas_tank_information_withdraw_zero_balance"
        }

        guard let balance = DecimalParser.parse(balanceNative), balance > 0 else {
            return "gas_tank_information_withdraw_zero_balance"
        }

        return nil
    }

    private func withdrawConfirmationModel() -> TransactionConfirmationModel {
        if let withdrawBlockReason {
            return TransactionConfirmationModel(
                title: "confirm_title",
                warning: withdrawBlockReason,
                details: [
                    TransactionConfirmationDetailModel(
                        label: "gas_tank_information_withdraw_all",
                        value: .text(String(localized: "gas_tank_information_withdraw_info")),
                    ),
                ],
                actions: [],
            )
        }

        let actionId = UUID()

        return TransactionConfirmationModel(
            title: "confirm_title",
            details: [
                TransactionConfirmationDetailModel(
                    label: "gas_tank_information_withdraw_all",
                    value: .text(String(localized: "gas_tank_information_withdraw_info")),
                ),
            ],
            actions: [
                TransactionConfirmationActionModel(
                    label: "profile_cancel",
                    variant: .neutral,
                ) {
                    pendingConfirmation = nil
                },
                TransactionConfirmationActionModel(
                    id: actionId,
                    label: "send_money_confirm_sign",
                    kind: .passkeyConfirmation,
                    isEnabled: onWithdrawAllFunds != nil,
                ) {
                    confirmWithdraw(actionId: actionId)
                },
            ],
        )
    }

    private func chainItem(
        chainID: UInt64,
        titleOverride: String? = nil,
    ) -> GasTankInformationChainItem {
        let chain = ChainRegistry.resolveOrFallback(chainID: chainID)
        return GasTankInformationChainItem(
            id: "\(chainID)",
            title: titleOverride ?? chain.name,
            assetName: chain.assetName,
        )
    }
}

#Preview {
    NavigationStack {
        GasTankInformationView(
            preferencesStore: PreferencesStore(),
            feeAbstractionStore: FeeAbstractionStore(),
            onWithdrawAllFunds: nil,
        )
    }
    .preferredColorScheme(.dark)
}
