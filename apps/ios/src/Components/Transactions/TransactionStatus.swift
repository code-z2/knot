import SwiftUI

enum TransactionStatus: Hashable {
    case success
    case failed

    var badgeText: String {
        switch self {
        case .success:
            String(localized: "transaction_status_success")
        case .failed:
            String(localized: "transaction_status_failed")
        }
    }

    var badgeIconSystemName: String {
        switch self {
        case .success:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var badgeTextColor: Color {
        switch self {
        case .success:
            AppThemeColor.accentGreen
        case .failed:
            AppThemeColor.accentRed
        }
    }

    var badgeBackgroundColor: Color {
        switch self {
        case .success:
            AppThemeColor.accentGreen.opacity(0.20)
        case .failed:
            AppThemeColor.accentRed.opacity(0.20)
        }
    }
}
