import SwiftUI

struct AppearancePickerModal: View {
    let selectedAppearance: AppAppearance
    let onSelect: (AppAppearance) -> Void

    var body: some View {
        HStack(spacing: 36) {
            ForEach(AppAppearance.allCases) { appearance in
                Button {
                    onSelect(appearance)
                } label: {
                    VStack(spacing: AppSpacing.xs) {
                        Text(appearance.localizedDisplayName)
                            .font(.custom("RobotoCondensed-Medium", size: 14))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .frame(height: 16)

                        AppearancePreviewCard(
                            appearance: appearance, isSelected: appearance == selectedAppearance,
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 42)
    }
}

private struct AppearancePreviewCard: View {
    let appearance: AppAppearance
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(AppThemeColor.gray2Light)
                    .frame(width: 12, height: 8)
                RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
                    .fill(AppThemeColor.gray2Light)
                    .frame(width: 32, height: 8)
            }

            RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
                .fill(AppThemeColor.gray2Light)
                .frame(width: 56, height: 22)

            VStack(spacing: AppSpacing.xs) {
                RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
                    .fill(AppThemeColor.gray2Light)
                    .frame(width: 56, height: 8)
                RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
                    .fill(AppThemeColor.gray2Light)
                    .frame(width: 56, height: 8)
            }
        }
        .padding(AppSpacing.sm)
        .frame(width: 80, height: 94, alignment: .topLeading)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                .stroke(
                    isSelected ? AppThemeColor.accentBrown : AppThemeColor.separatorOpaque, lineWidth: 1,
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous))
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch appearance {
        case .dark:
            AppThemeColor.grayBlack
        case .system:
            HStack(spacing: 0) {
                AppThemeColor.grayBlack
                AppThemeColor.grayWhite
            }
        case .light:
            AppThemeColor.grayWhite
        }
    }
}
