import SwiftUI
import UIKit

struct ProfileAvatarSectionView: View {
    let localAvatarImage: UIImage?
    let remoteAvatarURL: URL?
    let canEditProfileFields: Bool
    let onEditPhoto: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                avatarPreview
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(AppThemeColor.separatorOpaque, lineWidth: 1.5),
                    )

                Button(action: onEditPhoto) {
                    Text("Edit Photo")
                        .font(.custom("Roboto-Medium", size: 14))
                        .foregroundStyle(AppThemeColor.labelPrimary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.xxs)
                }
                .buttonStyle(.plain)
                .disabled(!canEditProfileFields)
                .opacity(canEditProfileFields ? 1 : 0.55)
                .background(AppThemeColor.fillSecondary)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let localAvatarImage {
            Image(uiImage: localAvatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let remoteAvatarURL {
            AsyncImage(url: remoteAvatarURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(AppThemeColor.backgroundPrimary)
            .overlay {
                Image(systemName: "person")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(AppThemeColor.separatorOpaque)
            }
    }
}
