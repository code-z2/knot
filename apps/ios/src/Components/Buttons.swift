import SwiftUI

public enum AppButtonVariant {
    case `default`
    case outline
    case destructive
    case neutral
}

public struct AppButton: View {
    let label: LocalizedStringKey
    let variant: AppButtonVariant
    let showLabel: Bool
    let showIcon: Bool
    let iconName: String?
    let foregroundColorOverride: Color?
    let backgroundColorOverride: Color?
    let action: () -> Void

    public init(
        label: LocalizedStringKey = "button_label_default",
        variant: AppButtonVariant = .default,
        showLabel: Bool = true,
        showIcon: Bool = false,
        iconName: String? = nil,
        foregroundColorOverride: Color? = nil,
        backgroundColorOverride: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.variant = variant
        self.showLabel = showLabel
        self.showIcon = showIcon
        self.iconName = iconName
        self.foregroundColorOverride = foregroundColorOverride
        self.backgroundColorOverride = backgroundColorOverride
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showLabel {
                    Text(label)
                        .font(.custom("Roboto-Bold", size: 15))
                        .foregroundStyle(foregroundColor)
                        .lineLimit(1)
                }

                if showIcon {
                    icon
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        if let iconName {
            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(foregroundColor)
        } else {
            Image("Icons/home_02")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(foregroundColor)
        }
    }

    private var foregroundColor: Color {
        if let foregroundColorOverride {
            return foregroundColorOverride
        }
        switch variant {
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

    @ViewBuilder
    private var background: some View {
        if let backgroundColorOverride {
            backgroundColorOverride
        } else {
            switch variant {
            case .default:
                AppThemeColor.accentBrown
            case .outline:
                Color.clear
            case .destructive:
                AppThemeColor.destructiveBackground
            case .neutral:
                AppThemeColor.fillPrimary
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AppButton(label: "button_label_default", variant: .default, showIcon: true) {}
        AppButton(label: "button_label_default", variant: .outline, showIcon: true) {}
        AppButton(label: "button_label_default", variant: .destructive, showIcon: true) {}
        AppButton(label: "button_label_default", variant: .neutral, showIcon: true) {}
    }
    .padding(20)
    .background(AppThemeColor.fixedDarkSurface)
}
