import SwiftUI

struct ToggleSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(AppThemeColor.accentBrown)
            .toggleStyle(.switch)
            .accessibilityLabel(Text("toggle_accessibility"))
    }
}

#Preview {
    ToggleSwitch(isOn: .constant(true))
}
