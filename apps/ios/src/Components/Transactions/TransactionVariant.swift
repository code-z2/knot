enum TransactionVariant: Hashable {
    case received
    case sent
    case contract
    case multichain

    var rowIconSystemName: String {
        switch self {
        case .received:
            "arrow.down"
        case .sent:
            "arrow.up.right"
        case .contract:
            "square.grid.2x2"
        case .multichain:
            "wallet.pass"
        }
    }
}
