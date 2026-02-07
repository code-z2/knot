import RPC
import SwiftUI

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

struct MockTransaction: Identifiable, Hashable {
  let id: String
  let status: TransactionStatus
  let variant: TransactionVariant
  let rowTitle: TransactionRowTitle
  let rowSubtitle: TransactionRowSubtitle?
  let assetChange: TransactionAssetChange?
  let explorerChainId: UInt64
  let explorerTransactionHash: String?
  let receiptAmountText: String?
  let receiptAmountSubtitleKey: String?
  let counterpartyLabelKey: String
  let counterpartyValue: String
  let counterpartyIcon: AppBadgeIcon
  let timestampText: String
  let typeKey: String
  let feeText: String
  let networkName: String
  let networkAssetName: String
  let accumulatedFromNetworkAssetNames: [String]
}

struct TransactionSection: Identifiable, Hashable {
  let id: String
  let title: String
  let transactions: [MockTransaction]
}

enum MockTransactionData {
  static let quickBalanceUSD = Decimal(string: "305234.66") ?? 0

  static let sections: [TransactionSection] = [
    .init(
      id: "mon_19_jan",
      title: "Mon, 19 Jan",
      transactions: [
        .init(
          id: "mon_received_usdc",
          status: .success,
          variant: .received,
          rowTitle: .received(assetSymbol: "USDC"),
          rowSubtitle: .on(networkName: "Base"),
          assetChange: .init(direction: .up, fiatUSD: 300.56, assetText: "299.90"),
          explorerChainId: 8453,
          explorerTransactionHash:
            "0x8f3f2c6514cf0e6b4dc9b2a13d7e58d3acb7c8f41d72416ff4ec9e4b7e2d6a77",
          receiptAmountText: "+$1,000.00",
          receiptAmountSubtitleKey: nil,
          counterpartyLabelKey: "transaction_label_from",
          counterpartyValue: "0xgfhrb•••hgtsk",
          counterpartyIcon: .symbol("Icons/arrow_down"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_receive",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: []
        ),
        .init(
          id: "mon_sent_usdc",
          status: .success,
          variant: .sent,
          rowTitle: .sent(assetSymbol: "USDC"),
          rowSubtitle: .from(networkName: "Ethereum"),
          assetChange: .init(direction: .down, fiatUSD: 300.56, assetText: "299.90"),
          explorerChainId: 1,
          explorerTransactionHash:
            "0x94b1f6f7658fdbe4296e5f27ae6b7d2cc4ab8b98c08f57b1fcb64d9113ca1cbe",
          receiptAmountText: "-$1,000.00",
          receiptAmountSubtitleKey: nil,
          counterpartyLabelKey: "transaction_label_to",
          counterpartyValue: "anyaogu.eth",
          counterpartyIcon: .symbol("Icons/arrow_up_right"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_send",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: []
        ),
        .init(
          id: "mon_received_eth",
          status: .success,
          variant: .received,
          rowTitle: .received(assetSymbol: "ETH"),
          rowSubtitle: .on(networkName: "Base"),
          assetChange: .init(direction: .up, fiatUSD: 300.56, assetText: "0.025.46"),
          explorerChainId: 8453,
          explorerTransactionHash:
            "0x31bf8f5ad1d2cb6f73900ff633fa4b76f6a8ef23e6f2148ead03be21b05096fd",
          receiptAmountText: "+$1,000.00",
          receiptAmountSubtitleKey: nil,
          counterpartyLabelKey: "transaction_label_from",
          counterpartyValue: "0xgfhrb•••hgtsk",
          counterpartyIcon: .symbol("Icons/arrow_down"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_receive",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: []
        ),
      ]
    ),
    .init(
      id: "sun_18_jan",
      title: "sun, 18 Jan",
      transactions: [
        .init(
          id: "sun_contract_with_change",
          status: .success,
          variant: .contract,
          rowTitle: .localized(key: "transaction_row_contract_interaction"),
          rowSubtitle: .on(networkName: "Uniswap"),
          assetChange: .init(direction: .down, fiatUSD: 300.56, assetText: "0.025.46"),
          explorerChainId: 1,
          explorerTransactionHash:
            "0x6e2869ebf6d03ae0a1ef8667f77cecb7351375b53f7857387b9de91c1231c8af",
          receiptAmountText: "-$1,000.00",
          receiptAmountSubtitleKey: nil,
          counterpartyLabelKey: "transaction_label_contract",
          counterpartyValue: "uniswap",
          counterpartyIcon: .network("unichain"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_contract_interaction",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: []
        ),
        .init(
          id: "sun_contract_no_change",
          status: .success,
          variant: .contract,
          rowTitle: .localized(key: "transaction_row_contract_interaction"),
          rowSubtitle: .on(networkName: "Uniswap"),
          assetChange: nil,
          explorerChainId: 1,
          explorerTransactionHash:
            "0xfbe4ca91ff53c545142c5b88eab1ab0cc012d2a3598e95546d6b5f02c7e2d94c",
          receiptAmountText: nil,
          receiptAmountSubtitleKey: nil,
          counterpartyLabelKey: "transaction_label_contract",
          counterpartyValue: "uniswap",
          counterpartyIcon: .network("unichain"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_contract_interaction",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: []
        ),
        .init(
          id: "sun_sent_failed",
          status: .failed,
          variant: .sent,
          rowTitle: .sent(assetSymbol: "USDC"),
          rowSubtitle: .from(networkName: "Ethereum"),
          assetChange: .init(direction: .down, fiatUSD: 300.56, assetText: "0.025.46"),
          explorerChainId: 1,
          explorerTransactionHash:
            "0x7e2915ccf6a5e64579c7f18205f8388fc8533d5e905f7e6a1f6f6f86f31d0e42",
          receiptAmountText: "-<$0.0001",
          receiptAmountSubtitleKey: "transaction_receipt_subtitle_gas_fee",
          counterpartyLabelKey: "transaction_label_to",
          counterpartyValue: "0xgfhrb•••hgtsk",
          counterpartyIcon: .symbol("Icons/arrow_up_right"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_send",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: []
        ),
      ]
    ),
    .init(
      id: "sat_17_jan",
      title: "sat, 17 Jan",
      transactions: [
        .init(
          id: "sat_multichain",
          status: .success,
          variant: .multichain,
          rowTitle: .localized(key: "transaction_row_multichain_transfer"),
          rowSubtitle: nil,
          assetChange: .init(direction: .up, fiatUSD: 300.56, assetText: "0.025.46"),
          explorerChainId: 1,
          explorerTransactionHash:
            "0x713a40f41d0ce2a301a50a0c9143af0ed65f226dcaec2f352d7fd32a6e9ef6b5",
          receiptAmountText: "-$1,000.00",
          receiptAmountSubtitleKey: nil,
          counterpartyLabelKey: "transaction_label_to",
          counterpartyValue: "anyaogu.eth",
          counterpartyIcon: .symbol("Icons/arrow_up_right"),
          timestampText: "01/17/2026, 3:15 am",
          typeKey: "transaction_type_multichain_transfer",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: ["ethereum", "unichain", "bnb-smart-chain", "base"]
        )
      ]
    ),
  ]
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
  let sections: [TransactionSection]
  let displayCurrencyCode: String
  let displayLocale: Locale
  let usdToSelectedRate: Decimal
  let onSelect: (MockTransaction) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      ForEach(sections) { section in
        VStack(alignment: .leading, spacing: 14) {
          Text(section.title)
            .font(.custom("Roboto-Bold", size: 15))
            .foregroundStyle(AppThemeColor.labelPrimary)

          VStack(alignment: .leading, spacing: 14) {
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
  let transaction: MockTransaction
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
              Image(transaction.variant.rowIconAssetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundStyle(AppThemeColor.glyphPrimary)
            }

          VStack(alignment: .leading, spacing: 2) {
            transaction.rowTitle.text
              .font(.custom("Roboto-Medium", size: 15))
              .foregroundStyle(AppThemeColor.labelPrimary)
              .multilineTextAlignment(.leading)

            if let subtitle = transaction.rowSubtitle {
              subtitle.text
                .font(.custom("Roboto-Regular", size: 12))
                .foregroundStyle(AppThemeColor.labelSecondary)
            }
          }
        }

        Spacer(minLength: 8)

        if let change = transaction.assetChange {
          VStack(alignment: .trailing, spacing: 4) {
            Text(formattedFiatText(change))
              .font(.custom("RobotoMono-Medium", size: 12))
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
  let transaction: MockTransaction

  var body: some View {
    VStack(spacing: 0) {
      AppIconTextBadge(
        text: transaction.status.badgeText,
        icon: .symbol(transaction.status.badgeIconAssetName),
        textColor: transaction.status.badgeTextColor,
        backgroundColor: transaction.status.badgeBackgroundColor
      )
      .padding(.top, 22)

      if let amount = transaction.receiptAmountText {
        VStack(spacing: 9) {
          Text(amount)
            .font(.custom("RobotoMono-Bold", size: 20))
            .foregroundStyle(AppThemeColor.labelPrimary)
            .multilineTextAlignment(.center)

          if let receiptAmountSubtitleKey = transaction.receiptAmountSubtitleKey {
            Text(LocalizedStringKey(receiptAmountSubtitleKey))
              .font(.custom("Roboto-Medium", size: 12))
              .foregroundStyle(AppThemeColor.labelSecondary)
          }
        }
        .padding(.top, 36)
      }

      VStack(alignment: .leading, spacing: 16) {
        receiptField(label: LocalizedStringKey(transaction.counterpartyLabelKey)) {
          AppIconTextBadge(
            text: transaction.counterpartyValue,
            icon: transaction.counterpartyIcon
          )
        }

        receiptField(label: "transaction_receipt_time") {
          Text(transaction.timestampText)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }

        receiptField(label: "transaction_receipt_type") {
          Text(LocalizedStringKey(transaction.typeKey))
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }

        receiptField(label: "transaction_receipt_fee") {
          Text(transaction.feeText)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }

        receiptField(label: "transaction_receipt_network") {
          AppIconTextBadge(
            text: transaction.networkName,
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
      .padding(.top, transaction.receiptAmountText == nil ? 74 : 36)

      Spacer(minLength: 52)

      actionRow
        .padding(.bottom, 24)
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

  @Environment(\.openURL) private var openURL

  private func openExplorer() {
    guard
      let hash = transaction.explorerTransactionHash,
      let url = BlockExplorer.transactionURL(
        chainId: transaction.explorerChainId, transactionHash: hash)
    else {
      return
    }
    openURL(url, prefersInApp: true)
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    VStack(spacing: 24) {
      TransactionBalanceSummary(balanceText: "$305,234.66", isBalanceHidden: .constant(false))
      AccountTransactionsList(
        sections: MockTransactionData.sections,
        displayCurrencyCode: "USD",
        displayLocale: .current,
        usdToSelectedRate: 1
      ) { _ in }
    }
    .padding(20)
  }
}
