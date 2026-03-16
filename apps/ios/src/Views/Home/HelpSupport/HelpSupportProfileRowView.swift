import NukeUI
import SwiftUI

struct HelpSupportProfileRowView: View {
    let eoaAddress: String

    let profileName: String?

    let profileAvatarURL: URL?

    let ensTLD: String

    var body: some View {
        NavigationLink(value: AppRootDestination.profile) {
            HStack(spacing: AppSpacing.sm) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    if let displayName {
                        Text(displayName)
                            .font(.custom("RobotoMono-Medium", size: 16))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .lineLimit(1)
                    } else {
                        Text("home_profile")
                            .font(.custom("Roboto-Medium", size: 15))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .lineLimit(1)
                    }

                    Text(shortAddress)
                        .font(.custom("RobotoMono-Regular", size: 12))
                        .foregroundStyle(AppThemeColor.labelSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                ChevronIcon()
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(AppThemeColor.backgroundSecondary)
            .clipShape(.rect(cornerRadius: 27))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        if let profileAvatarURL {
            LazyImage(url: profileAvatarURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
                .frame(width: 36, height: 36)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(AppThemeColor.fillPrimary)

            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppThemeColor.labelPrimary)
        }
    }

    private var displayName: String? {
        guard let profileName, !profileName.isEmpty else { return nil }
        return "\(profileName)\(ensTLD)"
    }

    private var shortAddress: String {
        AddressShortener.shortened(eoaAddress, separator: "•••")
    }
}
