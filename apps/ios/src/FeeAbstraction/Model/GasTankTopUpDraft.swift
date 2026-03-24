import Foundation

struct GasTankTopUpDraft: Hashable, Sendable {
    let destinationAddress: String
    let destinationChainID: UInt64
    let fundingAssetID: String
    let fundingAssetSymbol: String
    let amountInput: String
}
