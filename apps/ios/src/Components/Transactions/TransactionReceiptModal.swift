import RPC
import SwiftUI
import Transactions

struct TransactionReceiptModal: View {
    let transaction: TransactionRecord
    let displayCurrencyCode: String
    let displayLocale: Locale
    let usdToSelectedRate: Decimal
    let onOpenExplorer: (URL) -> Void

    init(
        transaction: TransactionRecord,
        displayCurrencyCode: String = "USD",
        displayLocale: Locale = .current,
        usdToSelectedRate: Decimal = 1,
        onOpenExplorer: @escaping (URL) -> Void = { _ in }
    ) {
        self.transaction = transaction
        self.displayCurrencyCode = displayCurrencyCode
        self.displayLocale = displayLocale
        self.usdToSelectedRate = usdToSelectedRate
        self.onOpenExplorer = onOpenExplorer
    }

    private var receiptAmountText: String? {
        transaction.uiReceiptAmountText(
            displayCurrencyCode: displayCurrencyCode,
            displayLocale: displayLocale,
            usdToSelectedRate: usdToSelectedRate
        )
    }

    private var receiptFeeText: String {
        transaction.uiFeeText(
            displayCurrencyCode: displayCurrencyCode,
            displayLocale: displayLocale,
            usdToSelectedRate: usdToSelectedRate
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            AppIconTextBadge(
                text: transaction.uiStatus.badgeText,
                icon: .symbol(transaction.uiStatus.badgeIconSystemName),
                textColor: transaction.uiStatus.badgeTextColor,
                backgroundColor: transaction.uiStatus.badgeBackgroundColor
            )
            .padding(.top, 22)

            if let amount = receiptAmountText {
                VStack(spacing: 9) {
                    Text(amount)
                        .font(.custom("RobotoMono-Bold", size: 20))
                        .foregroundStyle(AppThemeColor.labelPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 36)
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                receiptField(label: LocalizedStringKey(transaction.uiCounterpartyLabelKey)) {
                    AppIconTextBadge(
                        text: transaction.uiCounterpartyValue,
                        icon: transaction.uiCounterpartyIcon
                    )
                }

                receiptField(label: "transaction_receipt_time") {
                    Text(transaction.uiTimestampText)
                        .font(.custom("RobotoMono-Medium", size: 14))
                        .foregroundStyle(AppThemeColor.labelPrimary)
                }

                receiptField(label: "transaction_receipt_type") {
                    Text(LocalizedStringKey(transaction.uiTypeKey))
                        .font(.custom("RobotoMono-Medium", size: 14))
                        .foregroundStyle(AppThemeColor.labelPrimary)
                }

                receiptField(label: "transaction_receipt_fee") {
                    Text(receiptFeeText)
                        .font(.custom("RobotoMono-Medium", size: 14))
                        .foregroundStyle(AppThemeColor.labelPrimary)
                }

                receiptField(label: "transaction_receipt_network") {
                    AppIconTextBadge(
                        text: transaction.chainName,
                        icon: .network(transaction.networkAssetName)
                    )
                }

                if !transaction.accumulatedFromNetworkAssetNames.isEmpty {
                    receiptField(label: "transaction_receipt_accumulated_from") {
                        MultiChainIconGroup(networkAssetNames: transaction.accumulatedFromNetworkAssetNames)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, receiptAmountText == nil ? 74 : 36)

            AppButton(
                label: "transaction_view_tx",
                variant: .outline,
                showIcon: true,
                iconName: "arrow.up.forward.app",
                action: openExplorer,
            )
            .padding(.top, AppSpacing.xl)
        }
        .padding(.horizontal, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func receiptField<Content: View>(
        label: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.custom("RobotoMono-Regular", size: 12))
                .foregroundStyle(AppThemeColor.labelSecondary)

            content()
        }
    }

    private func openExplorer() {
        let hash = transaction.txHash
        guard !hash.isEmpty,
              let url = BlockExplorer.transactionURL(
                chainId: transaction.chainId, transactionHash: hash)
        else {
            return
        }
        onOpenExplorer(url)
    }
}
