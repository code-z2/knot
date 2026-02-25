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
            "paperplane"
        case .contract:
            "wallet.pass"
        case .multichain:
            "arrow.trianglehead.merge"
        }
    }
}
