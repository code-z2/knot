import SwiftUI

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
