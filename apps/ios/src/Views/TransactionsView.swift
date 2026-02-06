import SwiftUI

struct TransactionsView: View {
  var onHomeTap: () -> Void = {}
  var onTransactionsTap: () -> Void = {}
  var onSessionKeyTap: () -> Void = {}

  @State private var isBalanceHidden = false
  @State private var selectedTransaction: MockTransaction?

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          AccountTransactionsList(sections: MockTransactionData.sections) { transaction in
            presentReceipt(for: transaction)
          }
          .padding(.horizontal, 20)
          .padding(.top, 35)
          .padding(.bottom, 24)
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      TransactionsAppHeader(
        balanceText: MockTransactionData.quickBalance,
        isBalanceHidden: $isBalanceHidden
      )
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      BottomNavigation(
        activeTab: .transactions,
        onHomeTap: onHomeTap,
        onTransactionsTap: onTransactionsTap,
        onSessionKeyTap: onSessionKeyTap
      )
    }
    .overlay(alignment: .bottom) {
      SlideModal(
        isPresented: selectedTransaction != nil,
        kind: .fullHeight(topInset: 12),
        onDismiss: dismissReceipt
      ) {
        if let selectedTransaction {
          TransactionReceiptModal(transaction: selectedTransaction)
        } else {
          EmptyView()
        }
      }
    }
  }

  private func presentReceipt(for transaction: MockTransaction) {
    withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
      selectedTransaction = transaction
    }
  }

  private func dismissReceipt() {
    selectedTransaction = nil
  }
}

private struct TransactionsAppHeader: View {
  let balanceText: String
  @Binding var isBalanceHidden: Bool

  var body: some View {
    VStack(spacing: 0) {
      TransactionBalanceSummary(
        balanceText: balanceText,
        isBalanceHidden: $isBalanceHidden
      )
      .padding(.horizontal, 20)
      .padding(.top, 35)
      .padding(.bottom, 10)

      Rectangle()
        .fill(AppThemeColor.separatorNonOpaque)
        .frame(height: 1)
    }
    .background(AppThemeColor.backgroundPrimary)
  }
}

#Preview {
  TransactionsView()
    .preferredColorScheme(.dark)
}
