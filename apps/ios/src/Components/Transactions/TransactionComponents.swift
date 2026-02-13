import RPC
import SwiftUI
import Transactions

enum TransactionStatus: Hashable {
  case success
  case failed

  var badgeText: String {
    switch self {
    case .success: String(localized: "transaction_status_success")
    case .failed: String(localized: "transaction_status_failed")
    }
  }

  var badgeIconAssetName: String {
    switch self {
    case .success: "Icons/check_verified_01"
    case .failed: "Icons/alert_circle"
    }
  }

  var badgeTextColor: Color {
    switch self {
    case .success: AppThemeColor.accentGreen
    case .failed: AppThemeColor.accentRed
    }
  }

  var badgeBackgroundColor: Color {
    switch self {
    case .success: AppThemeColor.accentGreen.opacity(0.20)
    case .failed: AppThemeColor.accentRed.opacity(0.20)
    }
  }
}

enum TransactionVariant: Hashable {
  case received
  case sent
  case contract
  case multichain

  var rowIconAssetName: String {
    switch self {
    case .received: "Icons/arrow_down"
    case .sent: "Icons/arrow_up_right"
    case .contract: "Icons/sticker_square"
    case .multichain: "Icons/wallet_02"
    }
  }
}

struct TransactionAssetChange: Hashable {
  enum Direction: Hashable {
    case up
    case down
  }

  let direction: Direction
  let fiatUSD: Decimal
  let assetText: String

  var accentColor: Color {
    switch direction {
    case .up: AppThemeColor.accentGreen
    case .down: AppThemeColor.accentRed
    }
  }
}

enum TransactionRowTitle: Hashable {
  case localized(key: String)
  case sent(assetSymbol: String)
  case received(assetSymbol: String)

  var text: Text {
    switch self {
    case .localized(let key):
      Text(LocalizedStringKey(key))
    case .sent(let assetSymbol):
      Text("transaction_row_action_sent") + Text(verbatim: " \(assetSymbol)")
    case .received(let assetSymbol):
      Text("transaction_row_action_received") + Text(verbatim: " \(assetSymbol)")
    }
  }
}

enum TransactionRowSubtitle: Hashable {
  case localized(key: String)
  case on(networkName: String)
  case from(networkName: String)

  var text: Text {
    switch self {
    case .localized(let key):
      Text(LocalizedStringKey(key))
    case .on(let networkName):
      Text("transaction_row_prefix_on") + Text(verbatim: " \(networkName)")
    case .from(let networkName):
      Text("transaction_row_prefix_from") + Text(verbatim: " \(networkName)")
    }
  }
}

// MARK: - TransactionRecord UI Extension

private let receiptDateFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "MM/dd/yyyy, h:mm a"
  return f
}()

extension TransactionRecord {
  var uiStatus: TransactionStatus {
    switch status {
    case .success: .success
    case .failed: .failed
    }
  }

  var uiVariant: TransactionVariant {
    switch variant {
    case .received: .received
    case .sent: .sent
    case .contract: .contract
    case .multichain: .multichain
    }
  }

  var uiRowTitle: TransactionRowTitle {
    switch variant {
    case .received: .received(assetSymbol: tokenSymbol)
    case .sent: .sent(assetSymbol: tokenSymbol)
    case .contract: .localized(key: "transaction_row_contract_interaction")
    case .multichain: .localized(key: "transaction_row_multichain_transfer")
    }
  }

  var uiRowSubtitle: TransactionRowSubtitle? {
    switch variant {
    case .received: .on(networkName: chainName)
    case .sent: .from(networkName: chainName)
    case .contract: .on(networkName: chainName)
    case .multichain: nil
    }
  }

  var uiAssetChange: TransactionAssetChange? {
    guard valueQuoteUSD != 0 || !assetAmountText.isEmpty else { return nil }
    let direction: TransactionAssetChange.Direction = variant == .received ? .up : .down
    return TransactionAssetChange(
      direction: direction,
      fiatUSD: valueQuoteUSD,
      assetText: assetAmountText
    )
  }

  var uiCounterpartyLabelKey: String {
    switch variant {
    case .received: "transaction_label_from"
    case .sent: "transaction_label_to"
    case .contract: "transaction_label_contract"
    case .multichain: "transaction_label_to"
    }
  }

  var uiCounterpartyValue: String {
    switch variant {
    case .received:
      return abbreviateAddress(fromAddress)
    case .sent:
      return abbreviateAddress(toAddress)
    case .contract:
      return abbreviateAddress(toAddress)
    case .multichain:
      if let recipient = multichainRecipient {
        return abbreviateAddress(recipient)
      }
      return abbreviateAddress(toAddress)
    }
  }

  var uiCounterpartyIcon: AppBadgeIcon {
    switch variant {
    case .received: .symbol("Icons/arrow_down")
    case .sent: .symbol("Icons/arrow_up_right")
    case .contract: .network(networkAssetName)
    case .multichain: .symbol("Icons/arrow_up_right")
    }
  }

  var uiTimestampText: String {
    receiptDateFormatter.string(from: blockSignedAt)
  }

  var uiTypeKey: String {
    switch variant {
    case .received: "transaction_type_receive"
    case .sent: "transaction_type_send"
    case .contract: "transaction_type_contract_interaction"
    case .multichain: "transaction_type_multichain_transfer"
    }
  }

  func uiFeeText(
    displayCurrencyCode: String,
    displayLocale: Locale,
    usdToSelectedRate: Decimal
  ) -> String {
    let converted = gasQuoteUSD * usdToSelectedRate
    if converted > 0, converted < 0.01 {
      let minimumDisplay = CurrencyDisplayFormatter.format(
        amount: 0.01,
        currencyCode: displayCurrencyCode,
        locale: displayLocale,
        minimumFractionDigits: 2,
        maximumFractionDigits: 4
      )
      return "<\(minimumDisplay)"
    }
    return CurrencyDisplayFormatter.format(
      amount: converted,
      currencyCode: displayCurrencyCode,
      locale: displayLocale,
      minimumFractionDigits: 2,
      maximumFractionDigits: 4
    )
  }

  func uiReceiptAmountText(
    displayCurrencyCode: String,
    displayLocale: Locale,
    usdToSelectedRate: Decimal
  ) -> String? {
    guard valueQuoteUSD != 0 else { return nil }
    let prefix = variant == .received ? "+" : "-"
    let converted = valueQuoteUSD * usdToSelectedRate
    let formatted = CurrencyDisplayFormatter.format(
      amount: converted,
      currencyCode: displayCurrencyCode,
      locale: displayLocale,
      minimumFractionDigits: 2,
      maximumFractionDigits: 4
    )
    return "\(prefix)\(formatted)"
  }

  private func abbreviateAddress(_ address: String) -> String {
    guard address.count > 10 else { return address }
    let prefix = address.prefix(6)
    let suffix = address.suffix(4)
    return "\(prefix)•••\(suffix)"
  }
}

struct TransactionBalanceSummary: View {
  let balanceText: String
  @Binding var isBalanceHidden: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
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
    VStack(alignment: .leading, spacing: 24) {
      ForEach(sections) { section in
        VStack(alignment: .leading, spacing: 16) {
          Text(section.title)
            .font(.custom("Roboto-Bold", size: 15))
            .foregroundStyle(AppThemeColor.labelPrimary)

          VStack(alignment: .leading, spacing: 16) {
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
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
            .frame(width: 24, height: 24)
            .overlay {
              Image(transaction.uiVariant.rowIconAssetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
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
          VStack(alignment: .trailing, spacing: 4) {
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
      .padding(.horizontal, 4)
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
        icon: .symbol(transaction.uiStatus.badgeIconAssetName),
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

      VStack(alignment: .leading, spacing: 16) {
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

      actionRow
        .padding(.top, 24)
    }
    .padding(.horizontal, 38)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var actionRow: some View {
    AppButton(
      label: "transaction_view_tx",
      variant: .outline,
      showIcon: true,
      iconName: "Icons/link_external_01",
      action: openExplorer
    )
    .frame(width: 129)
    .frame(maxWidth: .infinity)
  }

  private func receiptField<Content: View>(
    label: LocalizedStringKey,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
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

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    VStack(spacing: 24) {
      TransactionBalanceSummary(balanceText: "$305,234.66", isBalanceHidden: .constant(false))
      AccountTransactionsList(
        sections: [],
        displayCurrencyCode: "USD",
        displayLocale: .current,
        usdToSelectedRate: 1
      ) { _ in }
    }
    .padding(20)
  }
}
