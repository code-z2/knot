import RPC
import SwiftUI

struct NetworkModePullDown: View {
    @Binding var mode: ChainSupportMode

    var body: some View {
        Picker(selection: $mode) {
            Text("preferences_network_mode_mainnet")
                .tag(ChainSupportMode.limitedMainnet)
            Text("preferences_network_mode_testnet")
                .tag(ChainSupportMode.limitedTestnet)
        } label: {}
            .pickerStyle(.menu)
            .tint(AppThemeColor.labelSecondary)
            .accentColor(AppThemeColor.labelSecondary)
            .foregroundStyle(AppThemeColor.labelSecondary)
            .buttonStyle(.plain)
    }
}
