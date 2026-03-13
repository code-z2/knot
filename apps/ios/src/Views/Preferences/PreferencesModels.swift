import RPC
import SwiftUI

extension ChainSupportMode {
    var localizedDisplayName: LocalizedStringKey {
        switch self {
        case .mainnet:
            "preferences_network_mode_mainnet"
        case .testnet:
            "preferences_network_mode_testnet"
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
