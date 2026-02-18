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

    var badgeIconSystemName: String {
        switch self {
        case .success: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
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

    var rowIconSystemName: String {
        switch self {
        case .received: "arrow.down"
        case .sent: "arrow.up.right"
        case .contract: "square.grid.2x2"
        case .multichain: "wallet.pass"
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
        case let .localized(key):
            Text(LocalizedStringKey(key))
        case let .sent(assetSymbol):
            Text("\(Text("transaction_row_action_sent")) \(Text(verbatim: assetSymbol))")
        case let .received(assetSymbol):
            Text("\(Text("transaction_row_action_received")) \(Text(verbatim: assetSymbol))")
        }
    }
}

enum TransactionRowSubtitle: Hashable {
    case localized(key: String)
    case on(networkName: String)
    case from(networkName: String)

    var text: Text {
        switch self {
        case let .localized(key):
            Text(LocalizedStringKey(key))
        case let .on(networkName):
            Text("\(Text("transaction_row_prefix_on")) \(Text(verbatim: networkName))")
        case let .from(networkName):
            Text("\(Text("transaction_row_prefix_from")) \(Text(verbatim: networkName))")
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
            assetText: assetAmountText,
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
        case .received: .symbol("arrow.down")
        case .sent: .symbol("arrow.up.right")
        case .contract: .network(networkAssetName)
        case .multichain: .symbol("arrow.up.right")
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
        usdToSelectedRate: Decimal,
    ) -> String {
        let converted = gasQuoteUSD * usdToSelectedRate
        if converted > 0, converted < 0.01 {
            let minimumDisplay = CurrencyDisplayFormatter.format(
                amount: 0.01,
                currencyCode: displayCurrencyCode,
                locale: displayLocale,
                minimumFractionDigits: 2,
                maximumFractionDigits: 4,
            )
            return "<\(minimumDisplay)"
        }
        return CurrencyDisplayFormatter.format(
            amount: converted,
            currencyCode: displayCurrencyCode,
            locale: displayLocale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 4,
        )
    }

    func uiReceiptAmountText(
        displayCurrencyCode: String,
        displayLocale: Locale,
        usdToSelectedRate: Decimal,
    ) -> String? {
        guard valueQuoteUSD != 0 else { return nil }
        let prefix = variant == .received ? "+" : "-"
        let converted = valueQuoteUSD * usdToSelectedRate
        let formatted = CurrencyDisplayFormatter.format(
            amount: converted,
            currencyCode: displayCurrencyCode,
            locale: displayLocale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 4,
        )
        return "\(prefix)\(formatted)"
    }

    private func abbreviateAddress(_ address: String) -> String {
        AddressShortener.shortened(address)
    }
}
