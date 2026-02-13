import Balance
import SwiftUI
import UIKit

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
    GeometryReader { _ in
      ZStack {
        AppThemeColor.backgroundPrimary.ignoresSafeArea()

        VStack(spacing: 0) {
          ScrollView(showsIndicators: false) {
            contentSection
              .background(
                GeometryReader { proxy in
                  let offset = proxy.frame(in: .named("homeScroll")).minY
                  Color.clear
                    .onChange(of: offset) { _, newOffset in
                      handleOverscroll(offset: newOffset)
                    }
                }
              )
          }
          .coordinateSpace(name: "homeScroll")
          // .padding(.top, AppHeaderMetrics.contentTopPadding) override for home screen
          .padding(.top, 12)
        }
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
  @State private var hasTriggeredPullRefresh = false

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

  private var assetsSummaryText: String {
    let assetCount = balanceStore.balances.count
    let chainCount: Int
    if !balanceStore.activeChainIDs.isEmpty {
      chainCount = balanceStore.activeChainIDs.count
    } else {
      // Fallback: derive from balance data
      let uniqueChains = Set(balanceStore.balances.flatMap { $0.chainBalances.map(\.chainID) })
      chainCount = uniqueChains.count
    }

    guard assetCount > 0 else {
      return String(localized: "home_assets_summary_empty")
    }

    return String(localized: "home_assets_summary_dynamic \(assetCount) \(chainCount)")
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

      HStack(spacing: 0) {
        Button(action: onAddMoney) {
          Text("home_add_money")
            .font(.custom("Roboto-Bold", size: 15))
            .foregroundStyle(AppThemeColor.backgroundPrimary)
            .frame(minWidth: 120)
            .frame(height: 52)
            .padding(.horizontal, 8)
            .background(
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppThemeColor.accentBrown)
            )
        }
        .buttonStyle(.plain)

        Spacer(minLength: 0)

        Button(action: onSendMoney) {
          Text("home_send_money")
            .font(.custom("Roboto-Bold", size: 15))
            .foregroundStyle(AppThemeColor.backgroundPrimary)
            .frame(minWidth: 120)
            .frame(height: 52)
            .padding(.horizontal, 8)
            .background(
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppThemeColor.accentBrown)
            )
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 36)
    }
    .frame(height: 163)
    .padding(.top, 36)
  }

  private var contentSection: some View {
    VStack(alignment: .leading, spacing: 28) {
      balanceSection
        .frame(maxWidth: .infinity)
        .padding(.bottom, 22)
        .padding(.horizontal, 20)

      Rectangle()
        .foregroundColor(.clear)
        .frame(height: 4)
        .background(AppThemeColor.separatorOpaque)

      assetsSection
        .padding(.horizontal, 20)

      spaceSection
        .padding(.horizontal, 20)

      logoutSection
        .padding(.horizontal, 20)

      Spacer(minLength: 0)
    }
    .padding(.bottom, 36)
  }

  private var assetsSection: some View {
    VStack(alignment: .leading, spacing: 15) {
      Text("home_assets_title")
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HomeSettingsCard {
        HomeSettingsRow(
          title: Text(assetsSummaryText),
          action: presentAssetsModal
        ) {
            IconBadge(style: .neutral) {
            Image("Icons/coins_03")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 21, height: 21)
              .foregroundStyle(AppThemeColor.glyphPrimary)
          }
        }        .padding(.vertical, 2)

      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var spaceSection: some View {
    VStack(alignment: .leading, spacing: 15) {
      Text("home_space_title")
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HomeSettingsCard {
        HomeSettingsRow(
          title: Text("home_profile"),
          action: onProfileTap
        ) {
          IconBadge(style: .defaultStyle) {
            Image("Icons/user_01")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 21, height: 21)
              .foregroundStyle(AppThemeColor.glyphPrimary)
          }
        }
        .padding(.top, 2)
        HomeSettingsRowDivider()

        HomeSettingsRow(
          title: Text("home_preferences"),
          action: onPreferencesTap
        ) {
          IconBadge(style: .defaultStyle) {
            Image("Icons/hexagon_01")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 21, height: 21)
              .foregroundStyle(AppThemeColor.glyphPrimary)
          }
        }
        if showWalletBackup {
          HomeSettingsRowDivider()
          HomeSettingsRow(
            title: Text("home_wallet_backup"),
            action: onWalletBackupTap
          ) {
            IconBadge(style: .defaultStyle) {
              Image("Icons/wallet_04")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21, height: 21)
                .foregroundStyle(AppThemeColor.glyphPrimary)
            }
          }
        }
        HomeSettingsRowDivider()
        HomeSettingsRow(
          title: Text("home_address_book"),
          action: onAddressBookTap
        ) {
          IconBadge(style: .defaultStyle) {
            Image("Icons/users_01")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 21, height: 21)
              .foregroundStyle(AppThemeColor.glyphPrimary)
          }
        }
        HomeSettingsRowDivider()
        HomeSettingsRow(
          title: Text("home_ai_agent"),
          action: nil,
          showsChevron: false
        ) {
          IconBadge(style: .defaultStyle) {
            Image("Icons/cpu_chip_02")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 21, height: 21)
              .foregroundStyle(AppThemeColor.glyphPrimary)
          }
        }
        .padding(.bottom, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var logoutSection: some View {
    HomeSettingsCard {
      HomeSettingsRow(
        title: Text("home_logout"),
        action: onSignOut,
        showsChevron: false,
        isDestructive: true
      ) {
        IconBadge(style: .destructive) {
          Image("Icons/log_out_02")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 21, height: 21)
            .foregroundStyle(AppThemeColor.accentRed)
        }
      }
      .padding(.vertical, 2)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
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

  // MARK: - Pull-to-refresh

  /// Threshold (points) the user must overscroll before a refresh fires.
  private let pullRefreshThreshold: CGFloat = 60

  private func handleOverscroll(offset: CGFloat) {
    if offset > pullRefreshThreshold && !hasTriggeredPullRefresh {
      hasTriggeredPullRefresh = true

      if preferencesStore.hapticsEnabled {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }

      Task {
        await balanceStore.silentRefresh()
      }
    }

    // Reset once the user scrolls back to resting position.
    if offset <= 0 && hasTriggeredPullRefresh {
      hasTriggeredPullRefresh = false
    }
  }

}

private struct HomeSettingsCard<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    if #available(iOS 26.0, *) {
      VStack(spacing: 2) {
        content()
      }
      .background(AppThemeColor.backgroundSecondary)
      .clipShape(.rect(cornerRadius: 22))
    } else {
      VStack(spacing: 2) {
        content()
      }
      .background(AppThemeColor.backgroundSecondary)
      .clipShape(.rect(cornerRadius: 22))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(AppThemeColor.separatorNonOpaque, lineWidth: 1)
      }
    }
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
          .buttonStyle(.plain)
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
        HStack(alignment: .center, spacing: 10) {
          Image("Icons/chevron_right")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 12, height: 12)
            .foregroundStyle(AppThemeColor.glyphSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 54)
    .contentShape(Rectangle())
  }
}

private struct HomeSettingsRowDivider: View {
  var body: some View {
    Rectangle()
      .fill(AppThemeColor.separatorOpaque)
      .frame(height: 1)
      .padding(.leading, 58)
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
