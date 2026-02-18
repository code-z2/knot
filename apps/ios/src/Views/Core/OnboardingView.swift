import SwiftUI

struct OnboardingView: View {
    let onCreateWallet: () -> Void
    let onLogin: () -> Void
    @State private var showContent = false

    var body: some View {
        GeometryReader { geo in
            let contentX: CGFloat = 54
            let contentTop: CGFloat = (geo.size.height * 0.5833)
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
                        Text("onboarding_title")
                            .font(AppTypography.onboardingTitle)
                            .foregroundStyle(AppThemeColor.grayWhite)
                            .lineSpacing(0)
                            .frame(width: 294, alignment: .leading)

                        Text("onboarding_subtitle")
                            .font(AppTypography.onboardingBody)
                            .foregroundStyle(AppThemeColor.grayWhite)
                            .lineSpacing(0)
                            .frame(width: 294, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 12)

                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppThemeColor.offWhite)
                        .frame(width: 35, height: 7)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 12)

                    HStack(spacing: 0) {
                        AppButton(
                            label: "onboarding_create_wallet",
                            variant: .default,
                            showIcon: false,
                            backgroundColorOverride: AppThemeColor.accentBrown,
                            action: onCreateWallet,
                        )

                        Spacer()

                        AppButton(
                            label: "onboarding_log_in",
                            variant: .outline,
                            showIcon: false,
                            foregroundColorOverride: AppThemeColor.grayWhite,
                            action: onLogin,
                        )
                    }
                    .frame(width: 294)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 12)
                }
                .offset(x: contentX, y: contentTop)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                showContent = true
            }
        }
    }
}

#Preview {
    OnboardingView(onCreateWallet: {}, onLogin: {})
        .preferredColorScheme(.dark)
}
