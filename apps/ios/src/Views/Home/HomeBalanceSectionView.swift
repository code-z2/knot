import SwiftUI

struct HomeBalanceSectionView: View {
    let accountBalanceDisplay: String
    @Binding var isBalanceHidden: Bool
    let onAddMoney: () -> Void
    let onSendMoney: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            VStack(spacing: AppSpacing.md) {
                Text("home_balance_title")
                    .font(.custom("Roboto-Bold", size: 16))
                    .foregroundStyle(AppThemeColor.labelSecondary)

                HideableText(
                    text: accountBalanceDisplay,
                    isHidden: $isBalanceHidden,
                    font: .custom("RobotoMono-Bold", size: 24),
                )
                .animation(AppAnimation.gentle, value: accountBalanceDisplay)
            }
            .padding(.horizontal, 18)

            HStack(spacing: AppSpacing.md) {
                actionButton(title: "home_add_money", onTap: onAddMoney)
                actionButton(title: "home_send_money", onTap: onSendMoney)
            }
            .padding(.horizontal, 36)
        }
        .frame(height: 163)
    }

    private func actionButton(title: LocalizedStringKey, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(title)
                .font(.custom("Roboto-Bold", size: 15))
                .foregroundStyle(AppThemeColor.backgroundPrimary)
                .frame(minWidth: 128)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .tint(AppThemeColor.accentBrown)
    }
}
