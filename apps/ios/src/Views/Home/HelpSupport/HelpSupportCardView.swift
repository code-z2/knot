import SwiftUI

struct HelpSupportCardView<BodyContent: View>: View {
    let titleKey: LocalizedStringKey

    let systemName: String

    let iconBackground: Color

    let buttonLabelKey: LocalizedStringKey?

    let minHeight: CGFloat?

    let action: (() -> Void)?

    let bodyContent: () -> BodyContent

    init(
        titleKey: LocalizedStringKey,
        systemName: String,
        iconBackground: Color,
        buttonLabelKey: LocalizedStringKey? = nil,
        minHeight: CGFloat? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder bodyContent: @escaping () -> BodyContent,
    ) {
        self.titleKey = titleKey

        self.systemName = systemName

        self.iconBackground = iconBackground

        self.buttonLabelKey = buttonLabelKey

        self.minHeight = minHeight

        self.action = action

        self.bodyContent = bodyContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                iconBadge

                Text(titleKey)
                    .font(.custom("Roboto-Medium", size: 14))
                    .foregroundStyle(AppThemeColor.labelSecondary)
            }

            bodyContent()

            if let buttonLabelKey, let action {
                HStack {
                    Spacer(minLength: 0)

                    AppButton(
                        label: buttonLabelKey,
                        variant: .outline,
                        size: .compact,
                        foregroundColorOverride: AppThemeColor.labelSecondary,
                        action: action,
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
        .background(AppThemeColor.backgroundSecondary)
        .clipShape(.rect(cornerRadius: AppCornerRadius.lg))
    }

    private var iconBadge: some View {
        IconBadge(
            style: .solid(background: iconBackground, icon: AppThemeColor.grayWhite),
            contentPadding: 4,
            cornerRadius: 6,
            borderWidth: 0,
        ) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 14, height: 14)
        }
    }
}
