import SwiftUI

enum AppBadgeIcon: Hashable {
  case symbol(String)
  case network(String)
}

struct AppTextBadge: View {
  let text: String
  var textColor: Color = AppThemeColor.labelPrimary
  var backgroundColor: Color = AppThemeColor.fillTertiary

  var body: some View {
    HStack(spacing: 0) {
      Text(text)
        .font(.custom("RobotoMono-Regular", size: 14))
        .foregroundStyle(textColor)
        .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(backgroundColor)
    )
  }
}

struct AppIconTextBadge: View {
  let text: String
  let icon: AppBadgeIcon
  var textColor: Color = AppThemeColor.labelPrimary
  var backgroundColor: Color = AppThemeColor.fillTertiary

  var body: some View {
    HStack(spacing: 6) {
      badgeIconView(icon)

      Text(text)
        .font(.custom("RobotoMono-Regular", size: 14))
        .foregroundStyle(textColor)
        .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(backgroundColor)
    )
  }

  @ViewBuilder
  private func badgeIconView(_ icon: AppBadgeIcon) -> some View {
    switch icon {
    case .symbol(let iconName):
      Image(iconName)
        .renderingMode(.template)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 16, height: 16)
        .foregroundStyle(textColor)
    case .network(let assetName):
      Image(assetName)
        .resizable()
        .scaledToFill()
        .frame(width: 16, height: 16)
        .clipShape(Circle())
    }
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    VStack(alignment: .leading, spacing: 12) {
      AppTextBadge(text: "text badge")
      AppIconTextBadge(text: "icon badge", icon: .symbol("Icons/check_verified_01"))
      AppIconTextBadge(text: "Ethereum", icon: .network("ethereum"))
    }
    .padding(20)
  }
}
