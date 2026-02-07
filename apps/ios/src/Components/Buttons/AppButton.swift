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
    action: @escaping () -> Void
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
    .disabled(isInteractionDisabled)
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var icon: some View {
    if visualState == .loading {
      ProgressView()
        .tint(foregroundColor)
        .frame(width: iconSize, height: iconSize)
    } else if let iconName {
      Image(iconName)
        .renderingMode(.template)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(foregroundColor)
    } else {
      Image("Icons/home_02")
        .renderingMode(.template)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(foregroundColor)
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
      switch resolvedVariant {
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
    AppButton(label: "Sending", variant: .neutral, visualState: .loading, showIcon: true) {}
    AppButton(
      label: "Failed",
      variant: .destructive,
      visualState: .error,
      showIcon: true,
      iconName: "Icons/x_close",
      iconSize: 16
    ) {}
  }
  .padding(20)
  .background(AppThemeColor.fixedDarkSurface)
}
