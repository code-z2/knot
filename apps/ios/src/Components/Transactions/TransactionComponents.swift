import RPC
import SwiftUI
import Transactions

struct TransactionBalanceSummary: View {
    let balanceText: String
    @Binding var isBalanceHidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("transaction_balance_label")
                .font(.custom("Roboto-Medium", size: 12))
                .foregroundStyle(AppThemeColor.labelSecondary)

            HideableText(
                text: balanceText,
                isHidden: $isBalanceHidden,
                font: .custom("RobotoMono-Medium", size: 14)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AccountTransactionsList: View {
    let sections: [TransactionDateSection]
    let displayCurrencyCode: String
    let displayLocale: Locale
    let usdToSelectedRate: Decimal
    let onSelect: (TransactionRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(section.title)
                        .font(.custom("Roboto-Bold", size: 15))
                        .foregroundStyle(AppThemeColor.labelPrimary)

                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        ForEach(section.transactions) { transaction in
                            TransactionRow(
                                transaction: transaction,
                                displayCurrencyCode: displayCurrencyCode,
                                displayLocale: displayLocale,
                                usdToSelectedRate: usdToSelectedRate,
                                onTap: { onSelect(transaction) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransactionRow: View {
    let transaction: TransactionRecord
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
            locale: displayLocale
        )

        switch change.direction {
        case .up:
            return "+\(formatted)"
        case .down:
            return "-\(formatted)"
        }
    }
}

struct MultiChainIconGroup: View {
    let networkAssetNames: [String]
    private let iconSize: CGFloat = 24
    private let overlap: CGFloat = 12

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(networkAssetNames.enumerated()), id: \.offset) { index, assetName in
                Circle()
                    .fill(AppThemeColor.backgroundPrimary)
                    .overlay(
                        Circle().stroke(AppThemeColor.separatorNonOpaque, lineWidth: 1)
                    )
                    .frame(width: iconSize, height: iconSize)
                    .overlay {
                        Image(assetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(Circle())
                    }
                    .offset(x: CGFloat(index) * overlap)
            }
        }
        .frame(
            width: iconSize + CGFloat(max(networkAssetNames.count - 1, 0)) * overlap,
            height: iconSize,
            alignment: .leading
        )
    }
}

#Preview {
    ZStack {
        AppThemeColor.fixedDarkSurface.ignoresSafeArea()
        VStack(spacing: AppSpacing.xl) {
            TransactionBalanceSummary(balanceText: "$305,234.66", isBalanceHidden: .constant(false))
            AccountTransactionsList(
                sections: [],
                displayCurrencyCode: "USD",
                displayLocale: .current,
                usdToSelectedRate: 1
            ) { _ in }
        }
        .padding(AppSpacing.lg)
    }
}
