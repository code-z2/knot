import Balance
import Observation
import RPC
import SwiftUI

struct GasTankView: View {
    let eoaAddress: String
    let depositAddress: String?
    let balanceStore: BalanceStore
    let preferencesStore: PreferencesStore
    let currencyRateStore: CurrencyRateStore
    let feeAbstractionService: FeeAbstractionService
    let gasUsageProvider: any GasUsageProviding
    let onInfoTap: () -> Void
    let onAddMoneyConfirm: (GasTankTopUpDraft) -> Void

    @Bindable var feeAbstractionStore: FeeAbstractionStore

    @State private var activeModal: GasTankModal?
    @State private var isRefreshing = false
    @State private var refreshErrorMessage: String?
    @State private var animateHeroAssets = false
    @State private var selectionTrigger = 0
    @State private var overdraftActionState: AppButtonVisualState = .normal
    @State private var overdraftActionTask: Task<Void, Never>?
    @State private var usageSummary: GasUsageSummary = .empty

    private let iconSize: CGFloat = 14

    var body: some View {
        ZStack {
            AppBackgroundView()

            List {
                heroSection
                summarySection
                payAsYouGoSection

                if !feeAbstractionStore.payAsYouGoEnabled {
                    overdraftSection
                    usageByChainSection
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(AppSpacing.md)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshGasTank()
            }
        }
        .task(id: loadKey) {
            loadSnapshot()
            await refreshGasTank()
            animateHeroAssets = true
        }
        .appNavigation(
            titleKey: "gas_tank_title",
            displayMode: .inline,
            hidesBackButton: false,
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectionTrigger += 1
                    onInfoTap()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppThemeColor.labelSecondary)
                }
            }
        }
        .appNavigationScrollEdgeStyle()
        .sheet(item: $activeModal) { modal in
            AppSheet(kind: modal.sheetKind) {
                modalContent(for: modal)
            }
        }
        .onDisappear {
            overdraftActionTask?.cancel()
            overdraftActionTask = nil
        }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
    }

    private var loadKey: String {
        "\(eoaAddress.lowercased())-\(preferencesStore.chainSupportMode.rawValue)"
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                GasTankHeroView(animateAssets: animateHeroAssets)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text("gas_tank_gas_usage")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppThemeColor.labelPrimary)

                        Spacer(minLength: 0)

                        Text(balanceDisplayValue)
                            .font(AppTypography.bodyRegular)
                            .foregroundStyle(AppThemeColor.labelSecondary)
                            .contentTransition(.numericText())
                    }

                    GasTankUsageBarView(
                        segments: usageSegments,
                        isDimmed: feeAbstractionStore.payAsYouGoEnabled,
                    )
                }
                .padding(.bottom, AppSpacing.sm)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.md, bottom: 0, trailing: AppSpacing.md))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(currentUsageValue)
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.labelSecondary)
            } label: {
                Text("gas_tank_current_usage")
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.labelPrimary)
            }

            LabeledContent {
                Text(balanceDisplayValue)
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .contentTransition(.numericText())
            } label: {
                Text("gas_tank_available")
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.labelPrimary)
            }

            Button {
                selectionTrigger += 1
                activeModal = .addMoney
            } label: {
                HStack {
                    Text("gas_tank_add_money")
                        .font(AppTypography.bodyRegular)

                    Spacer(minLength: 0)

                    ChevronIcon()
                }
                .foregroundStyle(AppThemeColor.accentBrown)
            }
            .buttonStyle(.plain)
            .disabled(feeAbstractionStore.payAsYouGoEnabled)
        }
        .disabled(feeAbstractionStore.payAsYouGoEnabled)
        .opacity(feeAbstractionStore.payAsYouGoEnabled ? 0.45 : 1)
    }

    private var payAsYouGoSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { feeAbstractionStore.payAsYouGoEnabled },
                    set: { feeAbstractionStore.setPayAsYouGoEnabled($0) },
                )
            ) {
                HStack(spacing: AppSpacing.sm) {
                    iconBadge(
                        systemName: "sparkles",
                        color: Color(hex: "#DB34F2"),
                    )

                    Text("gas_tank_pay_as_you_go")
                        .font(AppTypography.bodyRegular)
                        .foregroundStyle(AppThemeColor.labelPrimary)
                }
            }
            .tint(AppThemeColor.accentBrown)
        } footer: {
            Text("gas_tank_pay_as_you_go_info")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppThemeColor.labelSecondary)
                .textCase(nil)
        }
    }

    private var overdraftSection: some View {
        Section {
            LabeledContent {
                Text(overdraftUsageValue)
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.labelSecondary)
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    iconBadge(
                        systemName: "drop.fill",
                        color: Color(hex: "#FF9230"),
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("gas_tank_overdraft_title")
                            .font(AppTypography.bodyRegular)
                            .foregroundStyle(AppThemeColor.labelPrimary)

                        Text("gas_tank_overdraft_usage")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppThemeColor.labelSecondary)
                    }
                }
            }

            LabeledContent {
                Text(overdraftLimitValue)
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.labelSecondary)
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    iconBadge(
                        systemName: "minus.circle.fill",
                        color: AppThemeColor.accentRed,
                    )

                    Text("gas_tank_overdraft_limit")
                        .font(AppTypography.bodyRegular)
                        .foregroundStyle(AppThemeColor.labelPrimary)
                }
            }

            GasTankActionRowView(
                label: feeAbstractionStore.overdraftEnabled
                    ? "gas_tank_disable_overdraft"
                    : "gas_tank_enable_overdraft",
                color: overdraftActionColor,
                visualState: overdraftActionState,
                isEnabled: feeAbstractionStore.isOverdraftEligible,
                isCentered: false,
                action: toggleOverdraft,
            )
        } footer: {
            Text(overdraftFooterKey)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppThemeColor.labelSecondary)
                .textCase(nil)
        }
        .animation(AppAnimation.gentle, value: feeAbstractionStore.overdraftEnabled)
    }

    private var usageByChainSection: some View {
        Section {
            ForEach(displayedChains, id: \.chainID) { chain in
                HStack(spacing: AppSpacing.sm) {
                    Image(chain.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())

                    Text(chain.name)
                        .font(AppTypography.bodyRegular)
                        .foregroundStyle(AppThemeColor.labelPrimary)

                    Spacer(minLength: 0)

                    Text("gas_tank_no_data")
                        .font(AppTypography.bodyRegular)
                        .foregroundStyle(AppThemeColor.labelSecondary)
                }
            }
        } header: {
            Text("gas_tank_usage_by_chain")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppThemeColor.labelSecondary)
        } footer: {
            Text("gas_tank_chain_usage_info")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppThemeColor.labelSecondary)
                .textCase(nil)
        }
        .textCase(nil)
    }

    private var usageSegments: [GasTankUsageSegment] {
        let available = max(balanceDecimal ?? 0, 0)
        let overdraftCapacity = abs(minimumAllowedDecimal ?? 0)
        let overdraftUsed = balanceDecimal.map { min(max(-$0, 0), overdraftCapacity) } ?? 0
        let totalCapacity = max(available + overdraftCapacity, 0.0001)

        var segments: [GasTankUsageSegment] = []

        if overdraftUsed > 0 {
            segments.append(
                GasTankUsageSegment(
                    id: "overdraft",
                    titleKey: "gas_tank_overdraft_title",
                    value: min(doubleValue(overdraftUsed / totalCapacity), 1),
                    color: Color(hex: "#FF9230"),
                )
            )
        }

        let availableRatio = min(doubleValue(available / totalCapacity), 1)
        segments.append(
            GasTankUsageSegment(
                id: "available",
                titleKey: "gas_tank_available",
                value: max(availableRatio, 0),
                color: AppThemeColor.accentBrown,
            )
        )

        if segments.allSatisfy({ $0.value == 0 }) {
            return [
                GasTankUsageSegment(
                    id: "available-default",
                    titleKey: "gas_tank_available",
                    value: 1,
                    color: AppThemeColor.accentBrown,
                ),
            ]
        }

        return normalizedSegments(segments)
    }

    private var displayedChains: [ChainDefinitionModel] {
        ChainRegistry.getChains()
    }

    private var currentUsageValue: String {
        usageSummary.totalUsageNative ?? String(localized: "gas_tank_no_activity")
    }

    private var balanceDisplayValue: String {
        if let balanceNative = feeAbstractionStore.balanceNative, !balanceNative.isEmpty {
            return balanceNative
        }

        if isRefreshing {
            return String(localized: "gas_tank_loading")
        }

        return String(localized: "gas_tank_no_data")
    }

    private var overdraftUsageValue: String {
        feeAbstractionStore.requiredTopUpNative ?? String(localized: "gas_tank_no_data")
    }

    private var overdraftLimitValue: String {
        feeAbstractionStore.minimumAllowedNative ?? String(localized: "gas_tank_no_data")
    }

    private var overdraftFooterKey: LocalizedStringKey {
        feeAbstractionStore.isOverdraftEligible
            ? "gas_tank_overdraft_info"
            : "gas_tank_overdraft_unavailable_info"
    }

    private var overdraftActionColor: Color {
        feeAbstractionStore.isOverdraftEligible
            ? AppThemeColor.accentBrown
            : AppThemeColor.labelSecondary
    }

    private var balanceDecimal: Decimal? {
        feeAbstractionStore.balanceNative.flatMap { DecimalParser.parse($0) }
    }

    private var minimumAllowedDecimal: Decimal? {
        feeAbstractionStore.minimumAllowedNative.flatMap { DecimalParser.parse($0) }
    }

    private func normalizedSegments(_ segments: [GasTankUsageSegment]) -> [GasTankUsageSegment] {
        let total = segments.reduce(0) { $0 + $1.value }
        guard total > 0 else { return segments }

        return segments.map { segment in
            GasTankUsageSegment(
                id: segment.id,
                titleKey: segment.titleKey,
                value: segment.value / total,
                color: segment.color,
            )
        }
    }

    private func doubleValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    private func loadSnapshot() {
        feeAbstractionStore.load(
            eoaAddress: eoaAddress,
            mode: preferencesStore.chainSupportMode,
        )
    }

    private func refreshGasTank() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let creditRefresh: Void = feeAbstractionService.refreshCredit(
                eoaAddress: eoaAddress,
                mode: preferencesStore.chainSupportMode,
                store: feeAbstractionStore,
            )
            async let usageFetch = gasUsageProvider.fetchUsageSummary(
                eoaAddress: eoaAddress,
                mode: preferencesStore.chainSupportMode,
            )

            try await creditRefresh
            usageSummary = try await usageFetch
            refreshErrorMessage = nil
        } catch {
            refreshErrorMessage = error.localizedDescription
        }
    }

    private func toggleOverdraft() {
        guard feeAbstractionStore.isOverdraftEligible, overdraftActionState != .loading else { return }
        selectionTrigger += 1
        overdraftActionState = .loading
        overdraftActionTask?.cancel()
        overdraftActionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(0.7))
            } catch { return }

            feeAbstractionStore.setOverdraftEnabled(!feeAbstractionStore.overdraftEnabled)
            overdraftActionState = .success

            do {
                try await Task.sleep(for: .seconds(0.7))
            } catch { return }
            overdraftActionState = .normal
        }
    }

    @ViewBuilder
    private func modalContent(for modal: GasTankModal) -> some View {
        switch modal {
        case .addMoney:
            GasTankAddMoneyView(
                depositAddress: depositAddress,
                balances: balanceStore.balances,
                preferencesStore: preferencesStore,
                currencyRateStore: currencyRateStore,
            ) { draft in
                activeModal = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    onAddMoneyConfirm(draft)
                }
            }
        }
    }

    @ViewBuilder
    private func iconBadge(
        systemName: String,
        color: Color,
    ) -> some View {
        IconBadge(
            style: .solid(background: color, icon: AppThemeColor.grayWhite),
            contentPadding: 4,
            cornerRadius: 6,
            borderWidth: 0,
        ) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: iconSize, height: iconSize)
        }
    }
}

#Preview {
    NavigationStack {
        GasTankView(
            eoaAddress: "0xFFF00000000000000000000000000000BBBB",
            depositAddress: "0xF5bB7b6AfB7B726A44443E84210e1934Bf3210EE",
            balanceStore: BalanceStore(),
            preferencesStore: PreferencesStore(),
            currencyRateStore: CurrencyRateStore(),
            feeAbstractionService: FeeAbstractionService(),
            gasUsageProvider: GasUsageService(),
            onInfoTap: {},
            onAddMoneyConfirm: { _ in },
            feeAbstractionStore: FeeAbstractionStore(),
        )
    }
    .preferredColorScheme(.dark)
}
