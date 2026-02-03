import SwiftUI

struct IconBadge<Content: View>: View {
  enum Style {
    case defaultStyle
    case neutral
    case destructive
  }

  let style: Style
  let content: () -> Content

  init(style: Style, @ViewBuilder content: @escaping () -> Content) {
    self.style = style
    self.content = content
  }

  var body: some View {
    content()
      .padding(8)
      .background(backgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var backgroundColor: Color {
    switch style {
    case .defaultStyle:
      return AppThemeColor.accentBrownLight.opacity(0.4)
    case .neutral:
      return AppThemeColor.fillPrimary
    case .destructive:
      return AppThemeColor.destructiveBackground
    }
  }
}

#Preview {
  VStack(spacing: 16) {
    IconBadge(style: .defaultStyle) {
      Image("Icons/refresh_cw_04")
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
    IconBadge(style: .neutral) {
      Image("Icons/refresh_cw_04")
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
    IconBadge(style: .destructive) {
      Image("Icons/refresh_cw_04")
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
  }
  .padding()
  .background(AppThemeColor.fixedDarkSurface)
}
