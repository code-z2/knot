import SwiftUI

struct OnboardingView: View {
  let onCreateWallet: () -> Void
  let onLogin: () -> Void

  var body: some View {
    GeometryReader { geo in
      let contentX: CGFloat = 54
      let contentTop: CGFloat = (geo.size.height * 0.5833) + 14
      let artWidth: CGFloat = 402
      let artHeight: CGFloat = 486
      let artX: CGFloat = (geo.size.width - artWidth) / 2
      let artY: CGFloat = contentTop - 40 - artHeight

      ZStack(alignment: .topLeading) {
        AppThemeColor.fixedDarkSurface.ignoresSafeArea()

        Image("OnboardingArt")
          .resizable()
          .interpolation(.high)
          .frame(width: artWidth, height: artHeight)
          .offset(x: artX, y: artY)

        VStack(alignment: .leading, spacing: 43) {
          VStack(alignment: .leading, spacing: 15) {
            Text("Skip Chains\nJust Pay.")
              .font(AppTypography.onboardingTitle)
              .foregroundStyle(AppThemeColor.grayWhite)
              .lineSpacing(0)
              .frame(width: 294, alignment: .leading)

            Text(
              "Agentic payments wallet. Enter an amount and let the wallet juggle between chains for you"
            )
            .font(AppTypography.onboardingBody)
            .foregroundStyle(AppThemeColor.grayWhite)
            .lineSpacing(0)
            .frame(width: 294, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
          }

          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(AppThemeColor.offWhite)
            .frame(width: 35, height: 7)

          HStack(spacing: 0) {
            AppButton(
              label: "Create Wallet",
              variant: .default,
              showIcon: false,
              backgroundColorOverride: AppThemeColor.accentBrownLight,
              action: onCreateWallet
            )

            Spacer()

            AppButton(
              label: "Log In",
              variant: .outline,
              showIcon: false,
              foregroundColorOverride: AppThemeColor.grayWhite,
              action: onLogin
            )
          }
          .frame(width: 294)
        }
        .offset(x: contentX, y: contentTop)
      }
    }
  }
}

#Preview {
  OnboardingView(onCreateWallet: {}, onLogin: {})
    .preferredColorScheme(.dark)
}
