import SwiftUI

struct SessionKeyView: View {
    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            AppThemeColor.fillSecondary,
                            style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [12, 10]),
                        )
                        .frame(width: 238, height: 313)
                        .rotationEffect(.degrees(19.5))

                    VStack(spacing: 110) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(AppThemeColor.fillPrimary)

                        AppButton(
                            label: "session_key_coming_soon",
                            variant: .outline,
                            showIcon: false,
                            action: {},
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
                titleColor: AppThemeColor.labelPrimary,
            )
        }
    }
}

#Preview {
    SessionKeyView()
}
