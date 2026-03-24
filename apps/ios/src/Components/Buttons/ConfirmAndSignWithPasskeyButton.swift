import SwiftUI

struct ConfirmAndSignWithPasskeyButton: View {
    let label: LocalizedStringKey
    let visualState: AppButtonVisualState
    let isEnabled: Bool
    let fullWidth: Bool
    let action: () -> Void

    init(
        label: LocalizedStringKey,
        visualState: AppButtonVisualState = .normal,
        isEnabled: Bool = true,
        fullWidth: Bool = true,
        action: @escaping () -> Void,
    ) {
        self.label = label
        self.visualState = visualState
        self.isEnabled = isEnabled
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        AppButton(
            fullWidth: fullWidth,
            label: label,
            variant: .default,
            visualState: visualState,
            size: .regular,
            showIcon: true,
            iconName: "person.badge.key.fill",
            iconSize: 16,
            action: action,
        )
        .disabled(!isEnabled)
    }
}
