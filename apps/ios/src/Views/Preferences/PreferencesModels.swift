import RPC
import SwiftUI

enum PreferencesModalModel: String, Identifiable {
    case appearance

    var id: String {
        rawValue
    }

    var sheetKind: AppSheetKind {
        .height(260)
    }
}

enum PreferencesPageModel {
    case main
    case currency
    case language

    var title: LocalizedStringKey {
        switch self {
        case .main:
            "preferences_title"
        case .currency:
            "sheet_currency_title"
        case .language:
            "sheet_language_title"
        }
    }
}

extension ChainSupportMode {
    var localizedDisplayName: LocalizedStringKey {
        switch self {
        case .limitedMainnet:
            "preferences_network_mode_mainnet"
        case .limitedTestnet:
            "preferences_network_mode_testnet"
        case .fullMainnet:
            "preferences_network_mode_mainnet_plus"
        }
    }
}

extension AppAppearance {
    var localizedDisplayName: LocalizedStringKey {
        switch self {
        case .dark:
            "preferences_appearance_dark"
        case .system:
            "preferences_appearance_system"
        case .light:
            "preferences_appearance_light"
        }
    }
}
