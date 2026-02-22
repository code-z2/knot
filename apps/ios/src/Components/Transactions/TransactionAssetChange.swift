import SwiftUI

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
        case .up:
            AppThemeColor.accentGreen
        case .down:
            AppThemeColor.accentRed
        }
    }
}
