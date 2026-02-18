import SwiftUI

enum SendMoneyField: Hashable {
    case address
    case chain
    case asset
}

enum SendMoneyStep: Hashable {
    case recipient
    case amount
    case success
}

struct SendMoneyDraft: Sendable {
    let toAddressOrENS: String
    let chainID: String
    let chainName: String
    let assetID: String
    let assetSymbol: String
}
