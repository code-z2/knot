import SwiftUI

struct SessionKeyView: View {
    var onHomeTap: () -> Void = {}
    var onTransactionsTap: () -> Void = {}
    var onSessionKeyTap: () -> Void = {}

    var body: some View {
        ZStack {
            AppThemeColor.fixedDarkSurface.ignoresSafeArea()

            VStack(spacing: 0) {
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
                            label: "session_key_coming_soon",
                            variant: .outline,
                            showIcon: false,
                            action: {}
                        )
                    }
                }
                .frame(height: 375)
                .padding(.top, AppHeaderMetrics.contentTopPadding)

                Spacer()

                Text("session_key_description")
                    .font(.custom("Roboto-Regular", size: 16))
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 140)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(
                title: "session_key_title",
                titleFont: .custom("Roboto-Medium", size: 24),
                titleColor: AppThemeColor.labelPrimary
            )
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
