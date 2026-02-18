import SwiftUI

public enum AppButtonVariant {
    case `default`
    case outline
    case destructive
    case neutral
}

public enum AppButtonSize {
    case regular
    case compact
}

public enum AppButtonVisualState {
    case normal
    case loading
    case error
}

public struct AppButton: View {
    let fullWidth: Bool
    let label: LocalizedStringKey
    let variant: AppButtonVariant
    let visualState: AppButtonVisualState
    let size: AppButtonSize
    let showLabel: Bool
    let showIcon: Bool
    let iconName: String?
    let iconSize: CGFloat
    let underlinedLabel: Bool
    let foregroundColorOverride: Color?
    let backgroundColorOverride: Color?
    let action: () -> Void

    public init(
        fullWidth: Bool = false,
        label: LocalizedStringKey = "button_label_default",
        variant: AppButtonVariant = .default,
        visualState: AppButtonVisualState = .normal,
        size: AppButtonSize = .regular,
        showLabel: Bool = true,
        showIcon: Bool = false,
        iconName: String? = nil,
        iconSize: CGFloat = 24,
        underlinedLabel: Bool = false,
        foregroundColorOverride: Color? = nil,
        backgroundColorOverride: Color? = nil,
        action: @escaping () -> Void,
    ) {
        self.fullWidth = fullWidth
        self.label = label
        self.variant = variant
        self.visualState = visualState
        self.size = size
        self.showLabel = showLabel
        self.showIcon = showIcon
        self.iconName = iconName
        self.iconSize = iconSize
        self.underlinedLabel = underlinedLabel
        self.foregroundColorOverride = foregroundColorOverride
        self.backgroundColorOverride = backgroundColorOverride
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showLabel {
                    Text(label)
                        .font(labelFont)
                        .underline(underlinedLabel, color: foregroundColor)
                        .foregroundStyle(foregroundColor)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }

                if showIcon {
                    icon
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .disabled(isInteractionDisabled)
        .buttonStyle(.borderedProminent)
        .tint(backgroundTint)
        .animation(AppAnimation.gentle, value: visualState)
    }

    @ViewBuilder
    private var icon: some View {
        if visualState == .loading {
            ProgressView()
                .tint(foregroundColor)
                .frame(width: iconSize, height: iconSize)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if let iconName {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(foregroundColor)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else {
            Image(systemName: "house")
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(foregroundColor)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private var isInteractionDisabled: Bool {
        visualState == .loading
    }

    private var resolvedVariant: AppButtonVariant {
        if visualState == .error {
            return .destructive
        }
        return variant
    }

    private var foregroundColor: Color {
        if let foregroundColorOverride {
            return foregroundColorOverride
        }
        switch resolvedVariant {
        case .default:
            return AppThemeColor.backgroundPrimary
        case .outline:
            return AppThemeColor.accentBrown
        case .destructive:
            return AppThemeColor.accentRed
        case .neutral:
            return AppThemeColor.labelSecondary
        }
    }

    private var labelFont: Font {
        switch size {
        case .regular:
            .custom("Roboto-Bold", size: 15)
        case .compact:
            .custom("Roboto-Medium", size: 14)
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular:
            18
        case .compact:
            AppSpacing.sm
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .regular:
            14
        case .compact:
            AppSpacing.xs
        }
    }

    private var backgroundTint: Color {
        if let backgroundColorOverride {
            return backgroundColorOverride
        }
        switch resolvedVariant {
        case .default:
            return AppThemeColor.accentBrown
        case .outline:
            return Color.clear
        case .destructive:
            return AppThemeColor.destructiveBackground
        case .neutral:
            return AppThemeColor.fillPrimary
        }
    }
}

#Preview {
    VStack(spacing: AppSpacing.lg) {
        AppButton(label: "button_label_default", variant: .default, showIcon: true) {}
        AppButton(label: "button_label_default", variant: .outline, showIcon: true) {}
        AppButton(label: "send_money_sending", variant: .neutral, visualState: .loading, showIcon: true)
            {}
        AppButton(
            label: "send_money_failed",
            variant: .destructive,
            visualState: .error,
            showIcon: true,
            iconName: "xmark.circle.fill",
            iconSize: 16,
        ) {}
    }
    .padding(AppSpacing.lg)
    .background(AppThemeColor.fixedDarkSurface)
}
