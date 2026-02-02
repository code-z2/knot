import SwiftUI

struct OnboardingView: View {
    let onCreateWallet: () -> Void
    let onLogin: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                AppThemeColor.fixedDarkSurface.ignoresSafeArea()

                Image("OnboardingEllipse1")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 73, height: 73)
                    .offset(x: 24, y: 32)

                Image("OnboardingEllipse2")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 280, height: 280)
                    .offset(x: -43, y: -72)

                Image("OnboardingEllipse4")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 280, height: 280)
                    .offset(x: (geo.size.width * 0.1667) + 47, y: -156)

                Image("OnboardingGroup1")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 224, height: 205.178)
                    .offset(x: 0, y: (geo.size.height * 0.25) + 61.5)

                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AppThemeColor.accentBrownLight)
                    .frame(width: 238, height: 313)
                    .rotationEffect(.degrees(19.5))
                    .offset(x: (geo.size.width * 0.3333) + 36, y: -47)

                Image("OnboardingRss")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 31.552, height: 31.552)
                    .rotationEffect(.degrees(153.39))
                    .offset(x: geo.size.width * 0.5851, y: (geo.size.height * 0.1667) + 42.19)

                VStack(alignment: .leading, spacing: 43) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Skip Chains\nJust Pay.")
                            .font(.custom("Roboto", size: 40).weight(.bold))
                            .foregroundStyle(AppThemeColor.fixedDarkText)
                            .lineSpacing(0)
                            .frame(width: 294, alignment: .leading)

                        Text("Agentic payments wallet. Enter an amount and let the wallet juggle between chains for you")
                            .font(.custom("Roboto", size: 15).weight(.medium))
                            .foregroundStyle(AppThemeColor.fixedDarkText)
                            .lineSpacing(0)
                            .frame(width: 294, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppThemeColor.offWhite)
                        .frame(width: 35, height: 7)

                    HStack(alignment: .bottom) {
                        Button(action: onCreateWallet) {
                            Text("Create Wallet")
                                .font(.custom("Roboto", size: 15).weight(.bold))
                                .foregroundStyle(AppThemeColor.backgroundPrimaryLight)
                                .frame(width: 151, height: 48.667)
                                .background(AppThemeColor.accentBrownLight, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        Button(action: onLogin) {
                            Text("Log In")
                                .font(.custom("Roboto", size: 15).weight(.bold))
                                .foregroundStyle(AppThemeColor.fixedDarkText)
                                .padding(.horizontal, 21)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 294)
                }
                .offset(x: 54, y: (geo.size.height * 0.5833) + 16.17)
            }
        }
    }
}

#Preview {
    OnboardingView(onCreateWallet: {}, onLogin: {})
        .preferredColorScheme(.dark)
}
