enum TransactionVariant: Hashable {
    case received
    case transfer
    case contract
    case multichain

    var rowIconSystemName: String {
        switch self {
        case .received:
            "arrow.down"
        case .transfer:
            "paperplane"
        case .contract:
            "wallet.pass"
        case .multichain:
            "arrow.trianglehead.merge"
        }
    }
}
