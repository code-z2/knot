import SwiftUI

enum TransactionStatus: Hashable {
  case success
  case failed

  var badgeText: String {
    switch self {
    case .success: "success"
    case .failed: "failed"
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
  let fiatText: String
  let assetText: String

  var accentColor: Color {
    switch direction {
    case .up: AppThemeColor.accentGreen
    case .down: AppThemeColor.accentRed
    }
  }
}

struct MockTransaction: Identifiable, Hashable {
  let id: String
  let dateLabel: String
  let status: TransactionStatus
  let variant: TransactionVariant
  let rowTitle: String
  let rowSubtitle: String?
  let assetChange: TransactionAssetChange?
  let receiptAmountText: String?
  let receiptAmountSubtitle: String?
  let counterpartyLabel: String
  let counterpartyValue: String
  let counterpartyIcon: AppBadgeIcon
  let timestampText: String
  let typeText: String
  let feeText: String
  let networkName: String
  let networkAssetName: String
  let accumulatedFromNetworkAssetNames: [String]
  let showsRepeatAction: Bool
}

struct TransactionSection: Identifiable, Hashable {
  let id: String
  let title: String
  let transactions: [MockTransaction]
}

enum MockTransactionData {
  static let quickBalance = "$305,234.66"

  static let sections: [TransactionSection] = [
    .init(
      id: "mon_19_jan",
      title: "Mon, 19 Jan",
      transactions: [
        .init(
          id: "mon_received_usdc",
          dateLabel: "Mon, 19 Jan",
          status: .success,
          variant: .received,
          rowTitle: "recieved USDC",
          rowSubtitle: "on base",
          assetChange: .init(direction: .up, fiatText: "+$300.56", assetText: "299.90"),
          receiptAmountText: "+$1,000.00",
          receiptAmountSubtitle: "1,000.00 USDC",
          counterpartyLabel: "From",
          counterpartyValue: "0xgfhrb•••hgtsk",
          counterpartyIcon: .symbol("Icons/arrow_down"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Receive",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: [],
          showsRepeatAction: false
        ),
        .init(
          id: "mon_sent_usdc",
          dateLabel: "Mon, 19 Jan",
          status: .success,
          variant: .sent,
          rowTitle: "sent USDC",
          rowSubtitle: "from ethereum",
          assetChange: .init(direction: .down, fiatText: "-$300.56", assetText: "299.90"),
          receiptAmountText: "-$1,000.00",
          receiptAmountSubtitle: "1,000.00 USDC",
          counterpartyLabel: "To",
          counterpartyValue: "anyaogu.eth",
          counterpartyIcon: .symbol("Icons/arrow_up_right"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Send",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: [],
          showsRepeatAction: true
        ),
        .init(
          id: "mon_received_eth",
          dateLabel: "Mon, 19 Jan",
          status: .success,
          variant: .received,
          rowTitle: "recieved ETH",
          rowSubtitle: "on base",
          assetChange: .init(direction: .up, fiatText: "+$300.56", assetText: "0.025.46"),
          receiptAmountText: "+$1,000.00",
          receiptAmountSubtitle: "1,000.00 USDC",
          counterpartyLabel: "From",
          counterpartyValue: "0xgfhrb•••hgtsk",
          counterpartyIcon: .symbol("Icons/arrow_down"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Receive",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: [],
          showsRepeatAction: false
        ),
      ]
    ),
    .init(
      id: "sun_18_jan",
      title: "sun, 18 Jan",
      transactions: [
        .init(
          id: "sun_contract_with_change",
          dateLabel: "sun, 18 Jan",
          status: .success,
          variant: .contract,
          rowTitle: "contract interaction",
          rowSubtitle: "on unswap",
          assetChange: .init(direction: .down, fiatText: "-$300.56", assetText: "0.025.46"),
          receiptAmountText: "-$1,000.00",
          receiptAmountSubtitle: "1,000.00 USDC",
          counterpartyLabel: "contract",
          counterpartyValue: "uniswap",
          counterpartyIcon: .network("unichain"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Contract interaction",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: [],
          showsRepeatAction: false
        ),
        .init(
          id: "sun_contract_no_change",
          dateLabel: "sun, 18 Jan",
          status: .success,
          variant: .contract,
          rowTitle: "contract interaction",
          rowSubtitle: "on unswap",
          assetChange: nil,
          receiptAmountText: nil,
          receiptAmountSubtitle: nil,
          counterpartyLabel: "contract",
          counterpartyValue: "uniswap",
          counterpartyIcon: .network("unichain"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Contract interaction",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: [],
          showsRepeatAction: false
        ),
        .init(
          id: "sun_sent_failed",
          dateLabel: "sun, 18 Jan",
          status: .failed,
          variant: .sent,
          rowTitle: "sent USDC",
          rowSubtitle: "from ethereum",
          assetChange: .init(direction: .down, fiatText: "-$300.56", assetText: "0.025.46"),
          receiptAmountText: "-<$0.0001",
          receiptAmountSubtitle: "gas fee",
          counterpartyLabel: "To",
          counterpartyValue: "0xgfhrb•••hgtsk",
          counterpartyIcon: .symbol("Icons/arrow_up_right"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Send",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: [],
          showsRepeatAction: true
        ),
      ]
    ),
    .init(
      id: "sat_17_jan",
      title: "sat, 17 Jan",
      transactions: [
        .init(
          id: "sat_multichain",
          dateLabel: "sat, 17 Jan",
          status: .success,
          variant: .multichain,
          rowTitle: "multi-chain transfer",
          rowSubtitle: nil,
          assetChange: .init(direction: .up, fiatText: "+$300.56", assetText: "0.025.46"),
          receiptAmountText: "-$1,000.00",
          receiptAmountSubtitle: "1,000.00 USDC",
          counterpartyLabel: "To",
          counterpartyValue: "anyaogu.eth",
          counterpartyIcon: .symbol("Icons/arrow_up_right"),
          timestampText: "01/17/2026, 3:15 am",
          typeText: "Multichain Transfer",
          feeText: "<$0.01",
          networkName: "Ethereum",
          networkAssetName: "ethereum",
          accumulatedFromNetworkAssetNames: ["ethereum", "unichain", "bnb-smart-chain", "base"],
          showsRepeatAction: true
        ),
      ]
    ),
  ]
}

struct TransactionBalanceSummary: View {
  let balanceText: String
  @Binding var isBalanceHidden: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Balance")
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
  let onSelect: (MockTransaction) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      ForEach(sections) { section in
        VStack(alignment: .leading, spacing: 14) {
          Text(section.title)
            .font(.custom("Roboto-Bold", size: 12))
            .foregroundStyle(AppThemeColor.labelPrimary)

          VStack(alignment: .leading, spacing: 14) {
            ForEach(section.transactions) { transaction in
              TransactionRow(
                transaction: transaction,
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
                .frame(width: 10, height: 10)
                .foregroundStyle(AppThemeColor.glyphPrimary)
            }

          VStack(alignment: .leading, spacing: 2) {
            Text(transaction.rowTitle)
              .font(.custom("Roboto-Medium", size: 14))
              .foregroundStyle(AppThemeColor.labelPrimary)
              .multilineTextAlignment(.leading)

            if let subtitle = transaction.rowSubtitle {
              Text(subtitle)
                .font(.custom("Roboto-Regular", size: 12))
                .foregroundStyle(AppThemeColor.labelSecondary)
            }
          }
        }

        Spacer(minLength: 8)

        if let change = transaction.assetChange {
          VStack(alignment: .trailing, spacing: 4) {
            Text(change.fiatText)
              .font(.custom("RobotoMono-Medium", size: 12))
              .foregroundStyle(change.accentColor)
              .tracking(0.06)

            Text(change.assetText)
              .font(.custom("Roboto-Regular", size: 10))
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

          if let receiptAmountSubtitle = transaction.receiptAmountSubtitle {
            Text(receiptAmountSubtitle)
              .font(.custom("Roboto-Medium", size: 12))
              .foregroundStyle(AppThemeColor.labelSecondary)
          }
        }
        .padding(.top, 36)
      }

      VStack(alignment: .leading, spacing: 16) {
        receiptField(label: transaction.counterpartyLabel) {
          AppIconTextBadge(
            text: transaction.counterpartyValue,
            icon: transaction.counterpartyIcon
          )
        }

        receiptField(label: "Time") {
          Text(transaction.timestampText)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }

        receiptField(label: "Type") {
          Text(transaction.typeText)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }

        receiptField(label: "Fee") {
          Text(transaction.feeText)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }

        receiptField(label: "Network") {
          AppIconTextBadge(
            text: transaction.networkName,
            icon: .network(transaction.networkAssetName)
          )
        }

        if !transaction.accumulatedFromNetworkAssetNames.isEmpty {
          receiptField(label: "Accumulated from") {
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
    if transaction.showsRepeatAction {
      HStack(spacing: 12) {
        AppButton(
          label: "Repeat transfer",
          variant: .outline,
          showIcon: false,
          action: {}
        )
        .frame(width: 147)

        AppButton(
          label: "View Tx",
          variant: .outline,
          showIcon: true,
          iconName: "Icons/link_external_01",
          action: {}
        )
        .frame(width: 129)
      }
      .frame(maxWidth: .infinity)
    } else {
      AppButton(
        label: "View Tx",
        variant: .outline,
        showIcon: true,
        iconName: "Icons/link_external_01",
        action: {}
      )
      .frame(width: 129)
      .frame(maxWidth: .infinity)
    }
  }

  private func receiptField<Content: View>(
    label: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.custom("RobotoMono-Regular", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)

      content()
    }
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    VStack(spacing: 24) {
      TransactionBalanceSummary(balanceText: MockTransactionData.quickBalance, isBalanceHidden: .constant(false))
      AccountTransactionsList(sections: MockTransactionData.sections) { _ in }
    }
    .padding(20)
  }
}
