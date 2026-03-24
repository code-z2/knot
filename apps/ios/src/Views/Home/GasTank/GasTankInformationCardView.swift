import SwiftUI

struct GasTankInformationCardView: View {
    let supportedChains: [GasTankInformationChainItem]
    let withdrawActionState: AppButtonVisualState
    let onWithdrawTap: () -> Void

    private let columns = [
        GridItem(.fixed(96), spacing: AppSpacing.xl, alignment: .leading),
        GridItem(.fixed(96), spacing: AppSpacing.xl, alignment: .leading),
    ]

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image("gas-tank-3d")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 56)
                .accessibilityHidden(true)

            Text("gas_tank_information_heading")
                .font(AppTypography.heading)
                .foregroundStyle(AppThemeColor.labelPrimary)
                .multilineTextAlignment(.center)

            Text("gas_tank_information_intro")
                .font(AppTypography.bodyRegular)
                .foregroundStyle(AppThemeColor.labelPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: AppSpacing.md) {
                Text("gas_tank_information_supported_chains")
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(AppThemeColor.accentBrown)
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(supportedChains) { item in
                        GasTankSupportedChainBadgeView(item: item)
                    }
                }
                .frame(width: 216)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("gas_tank_information_cosigner")
                .font(AppTypography.bodyRegular)
                .foregroundStyle(AppThemeColor.labelPrimary)
                .multilineTextAlignment(.center)

            Rectangle()
                .fill(AppThemeColor.separatorOpaque)
                .frame(height: 1)

            GasTankActionRowView(
                label: "gas_tank_information_withdraw_all",
                color: AppThemeColor.accentBrown,
                visualState: withdrawActionState,
                isEnabled: true,
                isCentered: true,
                action: onWithdrawTap,
            )
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.lg)
        .background(AppThemeColor.backgroundSecondary)
        .clipShape(.rect(cornerRadius: AppCornerRadius.lg))
    }
}
