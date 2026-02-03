import SwiftUI

struct SessionKeyView: View {
  var onHomeTap: () -> Void = {}
  var onTransactionsTap: () -> Void = {}
  var onSessionKeyTap: () -> Void = {}

  var body: some View {
    ZStack {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()

      VStack(spacing: 0) {
        Text("Session Key")
          .font(.custom("Roboto-Medium", size: 24))
          .foregroundStyle(AppThemeColor.labelPrimary)
          .padding(.top, 47)
          .padding(.bottom, 44)

        ZStack {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              AppThemeColor.fillSecondary,
              style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [12, 10])
            )
            .frame(width: 238, height: 313)
            .rotationEffect(.degrees(19.5))

          VStack(spacing: 110) {
            Image("Icons/rss_01")
              .renderingMode(.template)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 24, height: 24)
              .foregroundStyle(AppThemeColor.fillPrimary)

            AppButton(
              label: "Coming Soon",
              variant: .outline,
              showIcon: false,
              action: {}
            )
          }
        }
        .frame(height: 375)

        Spacer()

        Text(
          "Each contactless session key card\nis a  temporary wallet with\npermissions to spend from your wallet.\nYou can customize these permissions\nafter setup."
        )
        .font(.custom("Roboto-Regular", size: 16))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .padding(.bottom, 140)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      BottomNavigation(
        activeTab: .sessionKey,
        onHomeTap: onHomeTap,
        onTransactionsTap: onTransactionsTap,
        onSessionKeyTap: onSessionKeyTap
      )
    }
  }
}

#Preview {
  SessionKeyView()
}
