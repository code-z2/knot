import SwiftUI

struct TransactionsAppHeader: View {
    let balanceText: String
    @Binding var isBalanceHidden: Bool

    var body: some View {
        VStack(spacing: 0) {
            TransactionBalanceSummary(
                balanceText: balanceText,
                isBalanceHidden: $isBalanceHidden,
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 35)
            .padding(.bottom, 10)

            Rectangle()
                .fill(AppThemeColor.separatorNonOpaque)
                .frame(height: 1)
        }
        .background(AppThemeColor.backgroundPrimary)
    }
}
