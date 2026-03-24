import SwiftUI

struct GasTankActionRowView: View {
    let label: LocalizedStringKey
    let color: Color
    let visualState: AppButtonVisualState
    let isEnabled: Bool
    let isCentered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(AppTypography.bodyRegular)
                    .foregroundStyle(isEnabled ? color : AppThemeColor.labelSecondary)
                    .frame(maxWidth: isCentered ? .infinity : nil, alignment: .center)

                Spacer(minLength: 0)

                trailingAccessory
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || visualState == .loading)
        .opacity(isEnabled ? 1 : 0.6)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch visualState {
        case .loading:
            ProgressView()
                .tint(color)
                .transition(.opacity)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppThemeColor.accentGreen)
                .transition(.opacity)
        case .error:
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppThemeColor.accentRed)
                .transition(.opacity)
        case .normal:
            EmptyView()
        }
    }
}
