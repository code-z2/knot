import SwiftUI

struct HomeView: View {
  let onSignOut: () -> Void
  let onAddMoney: () -> Void
  let onSendMoney: () -> Void
  let onHomeTap: () -> Void
  let onTransactionsTap: () -> Void
  let onSessionKeyTap: () -> Void
  let onProfileTap: () -> Void
  let onPreferencesTap: () -> Void
  let onWalletBackupTap: () -> Void
  let onAddressBookTap: () -> Void
  let showWalletBackup: Bool

  init(
    onSignOut: @escaping () -> Void,
    onAddMoney: @escaping () -> Void = {},
    onSendMoney: @escaping () -> Void = {},
    onHomeTap: @escaping () -> Void = {},
    onTransactionsTap: @escaping () -> Void = {},
    onSessionKeyTap: @escaping () -> Void = {},
    onProfileTap: @escaping () -> Void = {},
    onPreferencesTap: @escaping () -> Void = {},
    onWalletBackupTap: @escaping () -> Void = {},
    onAddressBookTap: @escaping () -> Void = {},
    showWalletBackup: Bool = true
  ) {
    self.onSignOut = onSignOut
    self.onAddMoney = onAddMoney
    self.onSendMoney = onSendMoney
    self.onHomeTap = onHomeTap
    self.onTransactionsTap = onTransactionsTap
    self.onSessionKeyTap = onSessionKeyTap
    self.onProfileTap = onProfileTap
    self.onPreferencesTap = onPreferencesTap
    self.onWalletBackupTap = onWalletBackupTap
    self.onAddressBookTap = onAddressBookTap
    self.showWalletBackup = showWalletBackup
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        AppThemeColor.fixedDarkSurface.ignoresSafeArea()

        VStack(spacing: 0) {
          topHeader()
          ScrollView(showsIndicators: false) {
            contentSection
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      BottomNavigation(
        activeTab: .home,
        onHomeTap: onHomeTap,
        onTransactionsTap: onTransactionsTap,
        onSessionKeyTap: onSessionKeyTap
      )
    }
  }

  private func topHeader() -> some View {
    Text("Home")
      .font(.custom("Roboto-Medium", size: 24))
      .foregroundStyle(AppThemeColor.labelPrimary)
      .padding(.top, 8)
      .padding(.bottom, 12)
  }

  @State private var isBalanceHidden: Bool = false
  let accountBalance = "$12,450.88"

  private var balanceSection: some View {
    VStack(spacing: 44) {
      VStack(spacing: 16) {
        Text("Balance")
          .font(.custom("Roboto-Bold", size: 16))
          .foregroundStyle(AppThemeColor.labelSecondary)

        HideableText(
          text: accountBalance,
          isHidden: $isBalanceHidden,
          font: .custom("RobotoMono-Bold", size: 24)
        )
      }
      .padding(.horizontal, 18)

      HStack(spacing: 0) {
        Button(action: onAddMoney) {
          Text("Add money")
            .font(.custom("Roboto-Bold", size: 15))
            .foregroundStyle(AppThemeColor.backgroundPrimary)
            .frame(width: 120, height: 52)
            .background(
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppThemeColor.accentBrown)
            )
        }
        .buttonStyle(.plain)

        Spacer(minLength: 0)

        Button(action: onSendMoney) {
          Text("Send money")
            .font(.custom("Roboto-Bold", size: 15))
            .foregroundStyle(AppThemeColor.backgroundPrimary)
            .frame(width: 120, height: 52)
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
    VStack(alignment: .leading, spacing: 32) {
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

      Spacer(minLength: 0)
    }
    .padding(.top, 0)
    .padding(.bottom, 50)
  }

  private var assetsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("YOUR ASSETS")
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 16) {
        ZStack(alignment: .topLeading) {
          IconBadge(style: .neutral) {
            Image("Icons/coins_03")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 21, height: 21)
              .foregroundColor(AppThemeColor.labelSecondary)
          }
          .frame(width: 37, height: 37)

          Image("Icons/currency_ethereum")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 10, height: 10)
            .offset(x: 11, y: 16)
            .foregroundColor(AppThemeColor.labelSecondary)
        }

        Text("7 Assets across 5 chains")
          .font(.custom("Roboto-Medium", size: 15))
          .foregroundStyle(AppThemeColor.labelSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var spaceSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("YOUR SPACE")
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 36) {
        VStack(spacing: 12) {
          MenuRow(
            title: "Profile",
            action: onProfileTap,
            leading: {
              IconBadge(style: .defaultStyle) {
                Image("Icons/user_01")
                  .renderingMode(.template)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 21, height: 21)
                  .foregroundColor(AppThemeColor.glyphPrimary)
              }
            }
          )
          MenuRow(
            title: "Preferences",
            action: onPreferencesTap,
            leading: {
              IconBadge(style: .defaultStyle) {
                Image("Icons/hexagon_01")
                  .renderingMode(.template)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 21, height: 21)
                  .foregroundColor(AppThemeColor.glyphPrimary)
              }
            }
          )
          if showWalletBackup {
            MenuRow(
              title: "Wallet Backup",
              action: onWalletBackupTap,
              leading: {
                IconBadge(style: .defaultStyle) {
                  Image("Icons/wallet_04")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 21, height: 21)
                    .foregroundColor(AppThemeColor.glyphPrimary)
                }
              }
            )
          }
          MenuRow(
            title: "Address Book",
            action: onAddressBookTap,
            leading: {
              IconBadge(style: .defaultStyle) {
                Image("Icons/users_01")
                  .renderingMode(.template)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 21, height: 21)
                  .foregroundColor(AppThemeColor.glyphPrimary)
              }
            }
          )
          MenuRow(
            title: "AI Agent",
            leading: {
              IconBadge(style: .defaultStyle) {
                Image("Icons/cpu_chip_02")
                  .renderingMode(.template)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 21, height: 21)
                  .foregroundColor(AppThemeColor.glyphPrimary)
              }
            }
          )
        }

        Button(action: onSignOut) {
          HStack(spacing: 16) {
            IconBadge(style: .destructive) {
              Image("Icons/log_out_02")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21, height: 21)
                .foregroundColor(AppThemeColor.accentRed)
            }

            Text("Logout")
              .font(.custom("Roboto-Medium", size: 15))
              .foregroundStyle(AppThemeColor.accentRed)
          }
        }
        .buttonStyle(.plain)
        .padding(.top, 28)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

}

private struct MenuRow<Leading: View>: View {
  let title: String
  let action: (() -> Void)?
  let leading: () -> Leading

  init(title: String, action: (() -> Void)? = nil, @ViewBuilder leading: @escaping () -> Leading) {
    self.title = title
    self.action = action
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
    HStack {
      HStack(spacing: 16) {
        leading()
        Text(title)
          .font(.custom("Roboto-Medium", size: 15))
          .foregroundStyle(AppThemeColor.labelPrimary)
      }

      Spacer(minLength: 0)

      HStack(alignment: .center, spacing: 10) {
        Image("Icons/chevron_right")
          .renderingMode(.template)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 12, height: 12)
          .foregroundColor(AppThemeColor.glyphSecondary)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 12)
      .cornerRadius(15)
    }
    .frame(maxWidth: .infinity, minHeight: 48)
  }
}

#Preview {
  HomeView(onSignOut: {})
    .preferredColorScheme(.dark)
}
