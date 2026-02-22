import SwiftUI

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
                font: .custom("RobotoMono-Medium", size: 14),
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
