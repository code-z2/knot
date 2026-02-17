import Balance
import SwiftUI

private enum HomeModal: String, Identifiable {
    case assets
    
    var id: String { rawValue }
    
    var sheetKind: AppSheetKind {
        switch self {
        case .assets:
            return .full
        }
    }
}

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
        showWalletBackup: Bool = true
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
        self.showWalletBackup = showWalletBackup
    }
    
    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                balanceSection
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                
                Rectangle()
                    .foregroundColor(.clear)
                    .frame(height: 4)
                    .background(AppThemeColor.separatorOpaque)
                
                settingsList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(
                title: "home_title",
                titleFont: .custom("Roboto-Medium", size: 24),
                titleColor: AppThemeColor.labelPrimary
            )
        }
        .task {}
        .sheet(item: $activeModal) { modal in
            AppSheet(kind: modal.sheetKind) {
                modalContent(for: modal)
            }
        }
    }
    
    @State private var isBalanceHidden: Bool = false
    @State private var activeModal: HomeModal?
    @State private var assetSearchText = ""
    private let groupedSectionGap: CGFloat = 16
    private let rowIconSize: CGFloat = 14
    private let rowBadgePadding: CGFloat = 6
    
    private var assetListState: AssetListState {
        balanceStore.isLoading ? .loading : .loaded(balanceStore.balances)
    }
    
    private var accountBalanceDisplay: String {
        currencyRateStore.formatUSD(
            balanceStore.totalValueUSD,
            currencyCode: preferencesStore.selectedCurrencyCode,
            locale: preferencesStore.locale
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
    
    private var balanceSection: some View {
        VStack(spacing: 44) {
            VStack(spacing: 16) {
                Text("home_balance_title")
                    .font(.custom("Roboto-Bold", size: 16))
                    .foregroundStyle(AppThemeColor.labelSecondary)
                
                HideableText(
                    text: accountBalanceDisplay,
                    isHidden: $isBalanceHidden,
                    font: .custom("RobotoMono-Bold", size: 24)
                )
            }
            .padding(.horizontal, 18)
            
            HStack(spacing: 16) {
                Button(action: onAddMoney) {
                    Text("home_add_money")
                        .font(.custom("Roboto-Bold", size: 15))
                        .foregroundStyle(AppThemeColor.backgroundPrimary)
                        .frame(minWidth: 128)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(AppThemeColor.accentBrown)
                
                Button(action: onSendMoney) {
                    Text("home_send_money")
                        .font(.custom("Roboto-Bold", size: 15))
                        .foregroundStyle(AppThemeColor.backgroundPrimary)
                        .frame(minWidth: 128)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(AppThemeColor.accentBrown)
            }
            .padding(.horizontal, 36)
        }
        .frame(height: 163)
    }
    
    private var settingsList: some View {
        List {
            Section {
                HomeSettingsRow(
                    title: assetsSummaryLabel,
                    action: presentAssetsModal
                ) {
                    IconBadge(
                        style: .solid(
                            background: Color(UIColor(.indigo)),
                            icon: AppThemeColor.grayWhite
                        ),
                        contentPadding: rowBadgePadding,
                        cornerRadius: 9,
                        borderWidth: 0
                    ) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: rowIconSize, weight: .medium))
                            .frame(width: rowIconSize, height: rowIconSize)
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(AppThemeColor.backgroundSecondary)
                        .padding(.vertical, 2)
                )
                .listRowSeparator(.hidden)
            } header: {
                sectionHeader("home_assets_title")
                    .padding(.top, groupedSectionGap)

            }
            .textCase(nil)
            
            Section {
                HomeSettingsRow(
                    title: Text("home_profile"),
                    action: onProfileTap
                ) {
                    IconBadge(
                        style: .solid(
                            background: Color(UIColor(.red)),
                            icon: AppThemeColor.grayWhite
                        ),
                        contentPadding: rowBadgePadding,
                        cornerRadius: 9,
                        borderWidth: 0
                    ) {
                        Image(systemName: "person")
                            .font(.system(size: rowIconSize, weight: .medium))
                            .frame(width: rowIconSize, height: rowIconSize)
                    }
                }
                
                HomeSettingsRow(
                    title: Text("home_preferences"),
                    action: onPreferencesTap
                ) {
                    IconBadge(
                        style: .solid(
                            background: Color(UIColor(.cyan)),
                            icon: AppThemeColor.grayWhite
                        ),
                        contentPadding: rowBadgePadding,
                        cornerRadius: 9,
                        borderWidth: 0
                    ) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: rowIconSize, weight: .medium))
                            .frame(width: rowIconSize, height: rowIconSize)
                    }
                }
                
                if showWalletBackup {
                    HomeSettingsRow(
                        title: Text("home_wallet_backup"),
                        action: onWalletBackupTap
                    ) {
                        IconBadge(
                            style: .solid(
                                background: Color(UIColor(.blue)),
                                icon: AppThemeColor.grayWhite
                            ),
                            contentPadding: rowBadgePadding,
                            cornerRadius: 9,
                            borderWidth: 0
                        ) {
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: rowIconSize, weight: .medium))
                                .frame(width: rowIconSize, height: rowIconSize)
                        }
                    }
                }
                
                HomeSettingsRow(
                    title: Text("home_address_book"),
                    action: onAddressBookTap
                ) {
                    IconBadge(
                        style: .solid(
                            background: Color(UIColor(.purple)),
                            icon: AppThemeColor.grayWhite
                        ),
                        contentPadding: rowBadgePadding,
                        cornerRadius: 9,
                        borderWidth: 0
                    ) {
                        Image(systemName: "person.2")
                            .font(.system(size: rowIconSize, weight: .medium))
                            .frame(width: rowIconSize, height: rowIconSize)
                    }
                }
                
                HomeSettingsRow(
                    title: Text("home_ai_agent"),
                    action: nil,
                    showsChevron: false
                ) {
                    IconBadge(
                        style: .gradient(colors: [Color(UIColor(.teal)), Color(UIColor(.orange))], icon: AppThemeColor.grayWhite),
                        contentPadding: rowBadgePadding,
                        cornerRadius: 9,
                        borderWidth: 0
                    ) {
                        Image(systemName: "cpu")
                            .font(.system(size: rowIconSize, weight: .medium))
                            .frame(width: rowIconSize, height: rowIconSize)
                    }
                }
            } header: {
                sectionHeader("home_space_title")
            }
            .textCase(nil)
            
            Section {
                HomeSettingsRow(
                    title: Text("home_logout"),
                    action: onSignOut,
                    showsChevron: false,
                    isDestructive: true
                ) {
                    Image(systemName: "circle")
                        .opacity(0)
                        .frame(width: 0)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(AppThemeColor.backgroundSecondary)
                )
                .listRowSeparator(.hidden)
            }
            .textCase(nil)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(groupedSectionGap)
        .scrollContentBackground(.hidden)
        .refreshable {
            await refreshBalances()
        }
    }
    
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelSecondary)
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
                usdToSelectedRate: currencyRateStore.rateFromUSD(to: preferencesStore.selectedCurrencyCode)
            )
        }
    }
    
    private func presentAssetsModal() {
        activeModal = .assets
    }
    
    private func refreshBalances() async {
        HapticFeedback.mediumImpact(enabled: preferencesStore.hapticsEnabled)
        await balanceStore.silentRefresh()
    }
    
}

private struct HomeSettingsRow<Leading: View>: View {
    let title: Text
    let action: (() -> Void)?
    let showsChevron: Bool
    let isDestructive: Bool
    let leading: () -> Leading
    
    init(
        title: Text,
        action: (() -> Void)? = nil,
        showsChevron: Bool = true,
        isDestructive: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.title = title
        self.action = action
        self.showsChevron = showsChevron
        self.isDestructive = isDestructive
        self.leading = leading
    }
    
    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
            } else {
                rowContent
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 12) {
            HStack(spacing: 16) {
                leading()
                
                title
                    .font(.custom("Roboto-Medium", size: 15))
                    .foregroundStyle(isDestructive ? AppThemeColor.accentRed : AppThemeColor.labelPrimary)
            }
            
            Spacer(minLength: 0)
            
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 12, height: 12)
                    .foregroundStyle(AppThemeColor.glyphSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct AssetsListModal: View {
    @Binding var query: String
    let state: AssetListState
    let displayCurrencyCode: String
    let displayLocale: Locale
    let usdToSelectedRate: Decimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchInput(text: $query, placeholderKey: "search_placeholder", width: nil)
                .padding(.horizontal, 20)
                .padding(.top, 13)
                .padding(.bottom, 21)
            
            Rectangle()
                .fill(AppThemeColor.separatorOpaque)
                .frame(height: 4)
            
            ScrollView(showsIndicators: false) {
                AssetList(
                    query: query,
                    state: state,
                    displayCurrencyCode: displayCurrencyCode,
                    displayLocale: displayLocale,
                    usdToSelectedRate: usdToSelectedRate
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    HomeView(
        balanceStore: BalanceStore(),
        preferencesStore: PreferencesStore(),
        currencyRateStore: CurrencyRateStore(),
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}
