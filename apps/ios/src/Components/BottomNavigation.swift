import SwiftUI

enum BottomNavigationTab {
  case home
  case transactions
  case sessionKey
}

struct BottomNavigation: View {
  let activeTab: BottomNavigationTab
  var onHomeTap: () -> Void = {}
  var onTransactionsTap: () -> Void = {}
  var onSessionKeyTap: () -> Void = {}

  var body: some View {
    HStack {
      tabItem(
        iconName: "Icons/home_02",
        title: "Home",
        titleWidth: 32,
        isActive: activeTab == .home,
        action: onHomeTap
      )

      Spacer(minLength: 0)

      tabItem(
        iconName: "Icons/receipt",
        title: "Transactions",
        titleWidth: 70,
        isActive: activeTab == .transactions,
        action: onTransactionsTap
      )
      .padding(.leading, 15)

      Spacer(minLength: 0)

      tabItem(
        iconName: "Icons/key_01",
        title: "Session Key",
        titleWidth: 70,
        isActive: activeTab == .sessionKey,
        action: onSessionKeyTap
      )
    }
    .padding(.top, 12)
    .padding(.horizontal, 40)
    .padding(.bottom, 6)
    .frame(maxWidth: .infinity, alignment: .top)
    .background(AppThemeColor.backgroundPrimary)
    .shadow(color: AppThemeColor.backgroundPrimary, radius: 8, x: 0, y: -8)
  }

  private func tabItem(
    iconName: String,
    title: String,
    titleWidth: CGFloat,
    isActive: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(iconName)
          .renderingMode(.template)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 22, height: 22)
          .foregroundStyle(isActive ? AppThemeColor.accentBrown : AppThemeColor.labelSecondary)
          .padding(.top, 2)

        Text(title)
          .font(.custom("Roboto-Medium", size: 11))
          .foregroundStyle(isActive ? AppThemeColor.accentBrown : AppThemeColor.labelSecondary)
          .tracking(0.5)
          .frame(width: titleWidth)
      }
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  VStack(spacing: 12) {
    BottomNavigation(activeTab: .home)
    BottomNavigation(activeTab: .transactions)
    BottomNavigation(activeTab: .sessionKey)
  }
  .padding()
  .background(AppThemeColor.fixedDarkSurface)
}
