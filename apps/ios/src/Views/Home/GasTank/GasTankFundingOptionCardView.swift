import SwiftUI

struct GasTankFundingOptionCardView: View {
    let assetImageName: String
    let symbol: String
    let balanceText: String
    let borderColor: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Image(assetImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)

                    Text(symbol)
                        .font(AppTypography.bodyLargeMedium)
                        .foregroundStyle(AppThemeColor.labelPrimary)
                }

                Text(balanceText)
                    .font(AppTypography.bodyMediumSmall)
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(width: 134, height: 73, alignment: .topLeading)
            .background(AppThemeColor.backgroundSecondary)
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                    .stroke(borderColor ?? Color.clear, lineWidth: borderColor == nil ? 0 : 2)
            }
            .clipShape(.rect(cornerRadius: AppCornerRadius.lg))
        }
        .buttonStyle(.plain)
    }
}
