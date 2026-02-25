import RPC
import SwiftUI

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
