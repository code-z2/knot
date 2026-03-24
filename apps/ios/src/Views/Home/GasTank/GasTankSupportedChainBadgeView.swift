import SwiftUI

struct GasTankSupportedChainBadgeView: View {
    let item: GasTankInformationChainItem

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let assetName = item.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
            } else if let fallbackHexColor = item.fallbackHexColor {
                Circle()
                    .fill(Color(hex: fallbackHexColor))
                    .frame(width: 18, height: 18)
            }

            Text(item.title)
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppThemeColor.labelPrimary)
                .lineLimit(1)
        }
    }
}
