import Balance
import SwiftUI
import Transactions

struct TransactionsView: View {
  let balanceStore: BalanceStore
  let transactionStore: TransactionStore
  let preferencesStore: PreferencesStore
  let currencyRateStore: CurrencyRateStore

  init(
    balanceStore: BalanceStore,
    transactionStore: TransactionStore,
    preferencesStore: PreferencesStore,
    currencyRateStore: CurrencyRateStore
  ) {
    self.balanceStore = balanceStore
    self.transactionStore = transactionStore
    self.preferencesStore = preferencesStore
    self.currencyRateStore = currencyRateStore
  }

  @State private var isBalanceHidden = false
  @State private var selectedTransaction: TransactionRecord?
  @Environment(\.openURL) private var openURL

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      if transactionStore.isLoading && transactionStore.sections.isEmpty {
        ProgressView()
          .tint(AppThemeColor.labelSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if transactionStore.sections.isEmpty {
        VStack(spacing: 12) {
          Text("transaction_empty_title")
            .font(.custom("Roboto-Medium", size: 15))
            .foregroundStyle(AppThemeColor.labelPrimary)
          Text("transaction_empty_subtitle")
            .font(.custom("Roboto-Regular", size: 13))
            .foregroundStyle(AppThemeColor.labelSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 0) {
            AccountTransactionsList(
              sections: transactionStore.sections,
              displayCurrencyCode: preferencesStore.selectedCurrencyCode,
              displayLocale: preferencesStore.locale,
              usdToSelectedRate: currencyRateStore.rateFromUSD(
                to: preferencesStore.selectedCurrencyCode)
            ) { transaction in
              presentReceipt(for: transaction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 35)
            .padding(.bottom, 24)

            if transactionStore.hasMore {
              ProgressView()
                .tint(AppThemeColor.labelSecondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
                .task {
                  await transactionStore.loadNextPage()
                }
            }
          }
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
    .sheet(item: $selectedTransaction) { transaction in
      AppSheet(kind: .full) {
        TransactionReceiptModal(
          transaction: transaction,
          displayCurrencyCode: preferencesStore.selectedCurrencyCode,
          displayLocale: preferencesStore.locale,
          usdToSelectedRate: currencyRateStore.rateFromUSD(
            to: preferencesStore.selectedCurrencyCode)
        ) { url in
          openExplorer(url)
        }
      }
    }
  }

  private func presentReceipt(for transaction: TransactionRecord) {
    selectedTransaction = transaction
  }

  private func dismissReceipt() {
    selectedTransaction = nil
  }

  private func openExplorer(_ url: URL) {
    dismissReceipt()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(180))
      openURL(url, prefersInApp: true)
    }
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
    transactionStore: TransactionStore(),
    preferencesStore: PreferencesStore(),
    currencyRateStore: CurrencyRateStore()
  )
  .preferredColorScheme(.dark)
}
