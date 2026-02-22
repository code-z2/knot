import SwiftUI
import Transactions

struct AccountTransactionsList: View {
    let sections: [TransactionDateSectionModel]
    let displayCurrencyCode: String
    let displayLocale: Locale
    let usdToSelectedRate: Decimal
    let onSelect: (TransactionRecordModel) -> Void

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
                                onTap: { onSelect(transaction) },
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
