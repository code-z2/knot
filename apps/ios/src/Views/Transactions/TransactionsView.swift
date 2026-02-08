import Balance
import SwiftUI

struct TransactionsView: View {
  let balanceStore: BalanceStore
  let preferencesStore: PreferencesStore
  let currencyRateStore: CurrencyRateStore
  var onHomeTap: () -> Void = {}
  var onTransactionsTap: () -> Void = {}
  var onSessionKeyTap: () -> Void = {}

  init(
    balanceStore: BalanceStore,
    preferencesStore: PreferencesStore,
    currencyRateStore: CurrencyRateStore,
    onHomeTap: @escaping () -> Void = {},
    onTransactionsTap: @escaping () -> Void = {},
    onSessionKeyTap: @escaping () -> Void = {}
  ) {
    self.balanceStore = balanceStore
    self.preferencesStore = preferencesStore
    self.currencyRateStore = currencyRateStore
    self.onHomeTap = onHomeTap
    self.onTransactionsTap = onTransactionsTap
    self.onSessionKeyTap = onSessionKeyTap
  }

  @State private var isBalanceHidden = false
  @State private var selectedTransaction: MockTransaction?

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          AccountTransactionsList(
            sections: MockTransactionData.sections,
            displayCurrencyCode: preferencesStore.selectedCurrencyCode,
            displayLocale: preferencesStore.locale,
            usdToSelectedRate: currencyRateStore.rateFromUSD(to: preferencesStore.selectedCurrencyCode)
          ) { transaction in
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
        balanceText: currencyRateStore.formatUSD(
          balanceStore.totalValueUSD,
          currencyCode: preferencesStore.selectedCurrencyCode,
          locale: preferencesStore.locale
        ),
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
    selectedTransaction = transaction
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
  TransactionsView(
    balanceStore: BalanceStore(),
    preferencesStore: PreferencesStore(),
    currencyRateStore: CurrencyRateStore()
  )
    .preferredColorScheme(.dark)
}
