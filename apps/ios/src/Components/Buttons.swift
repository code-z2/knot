import SwiftUI

public enum AppButtonStyle {
    case primary
    case outline
    case neutral
    case destructive
    case ghost
}

public struct AppButton: View {
    let title: String
    let icon: String?
    let style: AppButtonStyle
    let action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        style: AppButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)  // Assuming system images for now, can be changed to custom assets
                }
                Text(title)
            }
            .font(AppTypography.button)
            .foregroundStyle(textColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(height: 49)  // 48.667 rounded up
            .background(background)
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        switch style {
        case .primary: return AppThemeColor.backgroundPrimary
        case .outline: return AppThemeColor.accentBrown
        case .destructive: return AppThemeColor.accentRed
        case .neutral: return AppThemeColor.labelSecondary  // User specified labelSecondary for neutral
        case .ghost: return AppThemeColor.grayWhite  // Figma uses Grays/White
        }
    }

    private var horizontalPadding: CGFloat {
        style == .outline ? 21 : 18
    }

    private var verticalPadding: CGFloat {
        style == .outline ? 13 : 14
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppThemeColor.accentBrown)
        case .outline:
            Color.clear
        case .destructive:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppThemeColor.destructiveBackground)  // "rgba(255,56,60,0.14)" roughly matches this semantics
        case .neutral:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppThemeColor.fillPrimary)  // "rgba(120,120,120,0.2)" roughly matches
        case .ghost:
            Color.clear
        }
    }
}
