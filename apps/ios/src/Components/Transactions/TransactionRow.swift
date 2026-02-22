import RPC
import SwiftUI
import Transactions

struct TransactionRow: View {
    let transaction: TransactionRecordModel
    let displayCurrencyCode: String
    let displayLocale: Locale
    let usdToSelectedRate: Decimal
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: AppSpacing.sm) {
                    RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
                        .fill(AppThemeColor.fillPrimary)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: transaction.uiVariant.rowIconSystemName)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 16, height: 17)
                                .foregroundStyle(AppThemeColor.glyphPrimary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        transaction.uiRowTitle.text
                            .font(.custom("Roboto-Medium", size: 15))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .multilineTextAlignment(.leading)

                        if let subtitle = transaction.uiRowSubtitle {
                            subtitle.text
                                .font(.custom("Roboto-Regular", size: 12))
                                .foregroundStyle(AppThemeColor.labelSecondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                if let change = transaction.uiAssetChange {
                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(formattedFiatText(change))
                            .font(.custom("RobotoMono-Medium", size: 14))
                            .foregroundStyle(change.accentColor)
                            .tracking(0.06)

                        Text(change.assetText)
                            .font(.custom("Roboto-Regular", size: 12))
                            .foregroundStyle(AppThemeColor.labelSecondary)
                            .tracking(0.05)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func formattedFiatText(_ change: TransactionAssetChange) -> String {
        let converted = change.fiatUSD * usdToSelectedRate
        let formatted = CurrencyDisplayFormatter.format(
            amount: converted,
            currencyCode: displayCurrencyCode,
            locale: displayLocale,
        )

        switch change.direction {
        case .up:
            return "+\(formatted)"
        case .down:
            return "-\(formatted)"
        }
    }
}
