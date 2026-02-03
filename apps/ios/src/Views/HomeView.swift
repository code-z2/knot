import SwiftUI

struct HomeView: View {
    let onSignOut: () -> Void
    let onAddMoney: () -> Void
    let onSendMoney: () -> Void

    init(
        onSignOut: @escaping () -> Void,
        onAddMoney: @escaping () -> Void = {},
        onSendMoney: @escaping () -> Void = {}
    ) {
        self.onSignOut = onSignOut
        self.onAddMoney = onAddMoney
        self.onSendMoney = onSendMoney
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack {
                AppThemeColor.fixedDarkSurface.ignoresSafeArea()

                VStack(spacing: 0) {
                    topHeader(topInset: topInset)
                    contentSection
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNav
        }
    }

    private func topHeader(topInset: CGFloat) -> some View {
        Text("Home")
            .font(.custom("Roboto-Medium", size: 24).weight(.medium))
            .foregroundStyle(AppThemeColor.labelPrimary)
            .padding(.top, topInset + 12)
            .padding(.bottom, 45)
    }

    private var balanceSection: some View {
        VStack(spacing: 44) {
            VStack(spacing: 16) {
                Text("Balance")
                    .font(.custom("Roboto-Bold", size: 16).weight(.bold))
                    .foregroundStyle(AppThemeColor.labelSecondary)

                HStack(spacing: 8) {
                    Text("$305,234.66")
                        .font(.custom("RobotoMono-Bold", size: 40).weight(.bold))
                        .foregroundStyle(AppThemeColor.labelPrimary)

                    Image("Icons/eye")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 18)

            HStack(spacing: 0) {
                Button(action: onAddMoney) {
                    Text("Add money")
                        .font(.custom("Roboto-Bold", size: 15).weight(.bold))
                        .foregroundStyle(AppThemeColor.backgroundPrimary)
                        .frame(width: 113, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(AppThemeColor.accentBrown)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: onSendMoney) {
                    Text("Send money")
                        .font(.custom("Roboto-Bold", size: 15).weight(.bold))
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
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 32) {
            balanceSection
                .frame(maxWidth: .infinity)
                .padding(.bottom, 22)

            Rectangle()
                .fill(AppThemeColor.separatorOpaque)
                .frame(height: 1)

            assetsSection
            spaceSection
            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .padding(.horizontal, 20)
    }

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR ASSETS")
                .font(.custom("RobotoMono-Medium", size: 12).weight(.medium))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .frame(width: 362, alignment: .leading)

            HStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    IconBadge(style: .neutral) {
                        Image("Icons/coins_03")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 21, height: 17)
                    }
                    .frame(width: 37, height: 37)

                    Image("Icons/currency_ethereum")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10)
                        .offset(x: 11, y: 16)
                }

                Text("7 Assets across 5 chains")
                    .font(.custom("Roboto-Medium", size: 15).weight(.medium))
                    .foregroundStyle(AppThemeColor.labelSecondary)
            }
        }
        .frame(width: 362, height: 69, alignment: .topLeading)
    }

    private var spaceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR SPACE")
                .font(.custom("RobotoMono-Medium", size: 12).weight(.medium))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .frame(width: 362, alignment: .leading)

            VStack(alignment: .leading, spacing: 36) {
                VStack(spacing: 12) {
                    MenuRow(
                        title: "Preferences",
                        leading: {
                            IconBadge(style: .defaultStyle) {
                                Image("Icons/hexagon_01")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 21, height: 17)
                            }
                        }
                    )
                    MenuRow(
                        title: "Wallet Backup",
                        leading: {
                            IconBadge(style: .defaultStyle) {
                                Image("Icons/wallet_04")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 21, height: 21)
                            }
                        }
                    )
                    MenuRow(
                        title: "Address Book",
                        leading: {
                            IconBadge(style: .defaultStyle) {
                                Image("Icons/users_01")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 21, height: 17)
                            }
                        }
                    )
                    MenuRow(
                        title: "AI Agent",
                        leading: {
                            IconBadge(style: .defaultStyle) {
                                Image("Icons/cpu_chip_02")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 21, height: 17)
                            }
                        }
                    )
                }

                Button(action: onSignOut) {
                    HStack(spacing: 16) {
                        IconBadge(style: .destructive) {
                            Image("Icons/log_out_02")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 21, height: 17)
                        }

                        Text("Logout")
                            .font(.custom("Roboto-Medium", size: 15).weight(.medium))
                            .foregroundStyle(Color(hex: "#FF383C"))
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 362, alignment: .leading)
        }
        .frame(width: 362, height: 333, alignment: .topLeading)
    }

    private var bottomNav: some View {
        HStack {
            BottomNavItem(
                iconName: "Icons/home_02",
                title: "Home",
                textColor: AppThemeColor.accentBrown
            )
            Spacer(minLength: 0)
            BottomNavItem(
                iconName: "Icons/receipt",
                title: "Transactions",
                textColor: AppThemeColor.labelSecondary
            )
            Spacer(minLength: 0)
            BottomNavItem(
                iconName: "Icons/key_01",
                title: "Session Key",
                textColor: AppThemeColor.labelSecondary
            )
        }
        .padding(.top, 12)
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 84, alignment: .top)
        .background(AppThemeColor.backgroundPrimary)
    }
}

private struct BottomNavItem: View {
    let iconName: String
    let title: String
    let textColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .padding(.top, 2)

            Text(title)
                .font(.custom("Roboto-Medium", size: 11).weight(.medium))
                .foregroundStyle(textColor)
                .tracking(0.5)
        }
    }
}

private struct MenuRow<Leading: View>: View {
    let title: String
    let leading: () -> Leading

    init(title: String, @ViewBuilder leading: @escaping () -> Leading) {
        self.title = title
        self.leading = leading
    }

    var body: some View {
        HStack {
            HStack(spacing: 16) {
                leading()
                Text(title)
                    .font(.custom("Roboto-Medium", size: 15).weight(.medium))
                    .foregroundStyle(Color(hex: "#FFFFFF"))
            }

            Spacer(minLength: 0)

            Image("Icons/chevron_right")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
        }
        .frame(width: 362, height: 48)
    }
}

private struct IconBadge<Content: View>: View {
    enum Style {
        case defaultStyle
        case neutral
        case destructive
    }

    let style: Style
    let content: () -> Content

    init(style: Style, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.content = content
    }

    var body: some View {
        content()
            .frame(width: 21, height: 17)
            .padding(8)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var backgroundColor: Color {
        switch style {
        case .defaultStyle:
            return Color(hex: "#AC7F5E66")
        case .neutral:
            return AppThemeColor.fillPrimary
        case .destructive:
            return Color(hex: "#FF383C24")
        }
    }
}

#Preview {
    HomeView(onSignOut: {})
        .preferredColorScheme(.dark)
}
