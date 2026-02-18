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
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                .fill(backgroundColor),
        )
    }
}

struct AppIconTextBadge: View {
    let text: String
    let icon: AppBadgeIcon
    var textColor: Color = AppThemeColor.labelPrimary
    var backgroundColor: Color = AppThemeColor.fillTertiary
    var iconColor: Color?

    var body: some View {
        HStack(spacing: 6) {
            badgeIconView(icon, color: iconColor)

            Text(text)
                .font(.custom("RobotoMono-Regular", size: 14))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                .fill(backgroundColor),
        )
    }

    @ViewBuilder
    private func badgeIconView(_ icon: AppBadgeIcon, color: Color?) -> some View {
        switch icon {
        case let .symbol(iconName):
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 16, height: 16)
                .foregroundStyle(color ?? textColor)
        case let .network(assetName):
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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppTextBadge(text: "text badge")
            AppIconTextBadge(text: "icon badge", icon: .symbol("checkmark.seal.fill"))
            AppIconTextBadge(text: "Ethereum", icon: .network("ethereum"))
        }
        .padding(AppSpacing.lg)
    }
}
