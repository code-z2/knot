import SwiftUI

struct IconBadge<Content: View>: View {
  enum Style {
    case defaultStyle
    case neutral
    case destructive
    case solid(background: Color, icon: Color? = nil)
    case gradient(colors: [Color], icon: Color? = nil)
  }

  let style: Style
  let contentPadding: CGFloat
  let cornerRadius: CGFloat
  let borderWidth: CGFloat
  let content: () -> Content

  init(
    style: Style,
    contentPadding: CGFloat = 8,
    cornerRadius: CGFloat = 12,
    borderWidth: CGFloat = 1,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.style = style
    self.contentPadding = contentPadding
    self.cornerRadius = cornerRadius
    self.borderWidth = borderWidth
    self.content = content
  }

  var body: some View {
    badgeContent
      .padding(contentPadding)
      .background(backgroundFill)
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(borderColor, lineWidth: borderWidth)
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  @ViewBuilder
  private var badgeContent: some View {
    if let iconColor {
      content()
        .foregroundStyle(iconColor)
    } else {
      content()
    }
  }

  @ViewBuilder
  private var backgroundFill: some View {
    switch style {
    case .defaultStyle:
      AppThemeColor.accentBrown.opacity(0.32)
    case .neutral:
      AppThemeColor.fillPrimary
    case .destructive:
      AppThemeColor.destructiveBackground
    case .solid(let background, _):
      background
    case .gradient(let colors, _):
      if colors.count >= 2 {
        LinearGradient(
          colors: colors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      } else {
        (colors.first ?? AppThemeColor.fillPrimary)
      }
    }
  }

  private var borderColor: Color {
    switch style {
    case .destructive:
      return AppThemeColor.accentRed.opacity(0.2)
    default:
      return AppThemeColor.separatorNonOpaque.opacity(0.32)
    }
  }

  private var iconColor: Color? {
    switch style {
    case .solid(_, let icon):
      return icon
    case .gradient(_, let icon):
      return icon
    default:
      return nil
    }
  }
}

#Preview {
  VStack(spacing: 16) {
    IconBadge(style: .defaultStyle) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 16, weight: .medium))
    }
    IconBadge(style: .neutral) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 16, weight: .medium))
    }
    IconBadge(style: .destructive) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 16, weight: .medium))
    }
    IconBadge(
      style: .gradient(
        colors: [Color(hex: "#5F5AF7"), Color(hex: "#5AC8FA")],
        icon: AppThemeColor.grayWhite
      )
    ) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 16, weight: .medium))
    }
  }
  .padding()
  .background(AppThemeColor.fixedDarkSurface)
}
