import Balance
import RPC
import SwiftUI
import UIKit

struct GasTankAddMoneyView: View {
    let depositAddress: String?
    let balances: [TokenBalanceModel]
    let preferencesStore: PreferencesStore
    let currencyRateStore: CurrencyRateStore
    let onContinue: (GasTankTopUpDraft) -> Void

    @State private var selectedPresetUSD: Decimal = 2
    @State private var selectedFundingAssetID: String?
    @State private var copyTrigger = 0
    @State private var selectionTrigger = 0
    @State private var didCopyAddress = false
    @State private var copyResetTask: Task<Void, Never>?

    private let presetAmountsUSD: [Decimal] = [0.5, 1, 2, 5]

    init(
        depositAddress: String?,
        balances: [TokenBalanceModel],
        preferencesStore: PreferencesStore,
        currencyRateStore: CurrencyRateStore,
        onContinue: @escaping (GasTankTopUpDraft) -> Void,
    ) {
        self.depositAddress = depositAddress
        self.balances = balances
        self.preferencesStore = preferencesStore
        self.currencyRateStore = currencyRateStore
        self.onContinue = onContinue
        _selectedFundingAssetID = State(initialValue: Self.initialFundingAssetID(from: balances))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    amountSection
                    depositAddressSection
                    paymentSection
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.lg)
            }
            .scrollIndicators(.hidden)

            AppButton(fullWidth: true, label: "send_money_continue", variant: .default) {
                handleContinue()
            }
            .disabled(!canContinue)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
        }
        .onChange(of: balanceSelectionSignature) { _, _ in
            if selectedFundingAssetID == nil {
                selectedFundingAssetID = Self.initialFundingAssetID(from: balances)
            }
        }
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: copyTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("gas_tank_add_money_amount_prompt")
                .font(AppTypography.bodyRegular)
                .foregroundStyle(AppThemeColor.labelPrimary)

            HStack(spacing: AppSpacing.md) {
                ForEach(presetAmountsUSD, id: \.self) { amountUSD in
                    Button {
                        selectionTrigger += 1
                        selectedPresetUSD = amountUSD
                    } label: {
                        Text(presetTitle(for: amountUSD))
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(
                                selectedPresetUSD == amountUSD
                                    ? AppThemeColor.backgroundPrimary
                                    : AppThemeColor.labelPrimary,
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(
                                selectedPresetUSD == amountUSD
                                    ? AppThemeColor.accentBrown
                                    : AppThemeColor.backgroundSecondary,
                            )
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.lg)
        .background(AppThemeColor.backgroundTertiary)
        .clipShape(.rect(cornerRadius: AppCornerRadius.lg))
    }

    private var depositAddressSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("gas_tank_add_money_deposit_title")
                .font(AppTypography.bodyRegular)
                .foregroundStyle(AppThemeColor.labelPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.md) {
                    Text(displayDepositAddress)
                        .font(AppTypography.bodyRegular)
                        .foregroundStyle(AppThemeColor.labelPrimary)

                    Spacer(minLength: 0)

                    Button {
                        handleCopyAddress()
                    } label: {
                        Image(systemName: didCopyAddress ? "checkmark" : "square.on.square")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                didCopyAddress
                                    ? AppThemeColor.accentGreen
                                    : AppThemeColor.accentBrown,
                            )
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(depositAddress == nil)
                    .accessibilityLabel(Text("wallet_backup_copy"))
                }
                .padding(.horizontal, AppSpacing.lg)
                .frame(minHeight: 43)
                .background(AppThemeColor.backgroundTertiary)
                .clipShape(.rect(cornerRadius: AppCornerRadius.lg))

                Text("gas_tank_add_money_deposit_body")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("gas_tank_add_money_payment_prompt")
                .font(AppTypography.bodyRegular)
                .foregroundStyle(AppThemeColor.labelPrimary)

            LazyVGrid(
                columns: [
                    GridItem(.fixed(134), spacing: 36, alignment: .leading),
                    GridItem(.fixed(134), spacing: 36, alignment: .leading),
                ],
                alignment: .leading,
                spacing: AppSpacing.md,
            ) {
                ForEach(fundingOptions, id: \.id) { asset in
                    let definition = assetDefinition(for: asset)
                    GasTankFundingOptionCardView(
                        assetImageName: definition.assetImageName,
                        symbol: definition.displaySymbol,
                        balanceText: "\(asset.formattedBalance) \(definition.displaySymbol)",
                        borderColor: borderColor(for: asset),
                        action: {
                            selectionTrigger += 1
                            selectedFundingAssetID = asset.id
                        },
                    )
                }
            }
            .frame(width: 304, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.xl)
        .background(AppThemeColor.backgroundTertiary)
        .clipShape(.rect(cornerRadius: AppCornerRadius.lg))
    }

    private var fundingOptions: [TokenBalanceModel] {
        Self.fundingOptions(from: balances)
    }

    private var balanceSelectionSignature: [String] {
        balances.map(\.id)
    }

    private var selectedFundingAsset: TokenBalanceModel? {
        fundingOptions.first { $0.id == selectedFundingAssetID }
    }

    private var displayDepositAddress: String {
        guard let depositAddress, !depositAddress.isEmpty else {
            return String(localized: "gas_tank_no_data")
        }

        return AddressShortener.shortened(
            depositAddress,
            prefixCount: 6,
            suffixCount: 6,
            separator: "•••",
        )
    }

    private var selectedAmountInput: String {
        let converted = currencyRateStore.convertUSDToSelected(
            selectedPresetUSD,
            currencyCode: preferencesStore.selectedCurrencyCode,
        )

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""

        return formatter.string(from: converted as NSDecimalNumber) ?? "0"
    }

    private var destinationChainID: UInt64 {
        switch preferencesStore.chainSupportMode {
        case .mainnet:
            8_453
        case .testnet:
            84_532
        }
    }

    private var canContinue: Bool {
        depositAddress != nil && selectedFundingAsset != nil
    }

    private func presetTitle(for amountUSD: Decimal) -> String {
        currencyRateStore.formatUSD(
            amountUSD,
            currencyCode: preferencesStore.selectedCurrencyCode,
            locale: preferencesStore.locale,
        )
    }

    private func assetDefinition(for asset: TokenBalanceModel) -> GasTankFundingAssetDefinition {
        GasTankFundingAssetDefinition.supported.first(where: { $0.symbol == asset.symbol.uppercased() })
            ?? .init(
                symbol: asset.symbol.uppercased(),
                displaySymbol: asset.symbol,
                name: asset.name,
                assetImageName: "gas-tank-3d",
                decimals: asset.decimals,
                isNative: asset.isNative,
            )
    }

    private func handleCopyAddress() {
        guard let depositAddress else { return }

        UIPasteboard.general.string = depositAddress
        copyTrigger += 1
        didCopyAddress = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            didCopyAddress = false
        }
    }

    private func handleContinue() {
        guard
            let depositAddress,
            let selectedFundingAsset
        else {
            return
        }

        selectionTrigger += 1
        onContinue(
            GasTankTopUpDraft(
                destinationAddress: depositAddress,
                destinationChainID: destinationChainID,
                fundingAssetID: selectedFundingAsset.id,
                fundingAssetSymbol: selectedFundingAsset.symbol,
                amountInput: selectedAmountInput,
            )
        )
    }

    private func borderColor(for asset: TokenBalanceModel) -> Color? {
        guard selectedFundingAssetID == asset.id else { return nil }
        return AppThemeColor.accentBrown
    }

    private static func fundingOptions(from balances: [TokenBalanceModel]) -> [TokenBalanceModel] {
        GasTankFundingAssetDefinition.supported.map { definition in
            balances.first(where: { $0.symbol.uppercased() == definition.symbol }) ?? definition.placeholderBalance()
        }
    }

    private static func initialFundingAssetID(from balances: [TokenBalanceModel]) -> String? {
        let options = fundingOptions(from: balances)
        return options.first(where: { $0.totalValueUSD > 0 })?.id ?? options.first?.id
    }
}

#Preview {
    GasTankAddMoneyView(
        depositAddress: "0xF5bB7b6AfB7B726A44443E84210e1934Bf3210EE",
        balances: GasTankFundingAssetDefinition.previewBalances,
        preferencesStore: PreferencesStore(),
        currencyRateStore: CurrencyRateStore(),
        onContinue: { _ in },
    )
    .preferredColorScheme(.dark)
}
