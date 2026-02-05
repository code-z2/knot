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

public struct AppButton: View {
  let fullWidth: Bool
  let label: LocalizedStringKey
  let variant: AppButtonVariant
  let size: AppButtonSize
  let showLabel: Bool
  let showIcon: Bool
  let iconName: String?
  let underlinedLabel: Bool
  let foregroundColorOverride: Color?
  let backgroundColorOverride: Color?
  let action: () -> Void

  public init(
    fullWidth: Bool = false,
    label: LocalizedStringKey = "button_label_default",
    variant: AppButtonVariant = .default,
    size: AppButtonSize = .regular,
    showLabel: Bool = true,
    showIcon: Bool = false,
    iconName: String? = nil,
    underlinedLabel: Bool = false,
    foregroundColorOverride: Color? = nil,
    backgroundColorOverride: Color? = nil,
    action: @escaping () -> Void
  ) {
    self.fullWidth = fullWidth
    self.label = label
    self.variant = variant
    self.size = size
    self.showLabel = showLabel
    self.showIcon = showIcon
    self.iconName = iconName
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
        }

        if showIcon {
          icon
        }
      }
      .frame(maxWidth: fullWidth ? .infinity : nil)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
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

  private var labelFont: Font {
    switch size {
    case .regular:
      return .custom("Roboto-Bold", size: 15)
    case .compact:
      return .custom("Roboto-Medium", size: 14)
    }
  }

  private var horizontalPadding: CGFloat {
    switch size {
    case .regular:
      return 18
    case .compact:
      return 12
    }
  }

  private var verticalPadding: CGFloat {
    switch size {
    case .regular:
      return 14
    case .compact:
      return 8
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
