import SwiftUI

struct HelpSupportView: View {
    let eoaAddress: String

    let profileName: String?

    let profileAvatarURL: URL?

    let ensTLD: String

    @Environment(\.openURL) private var openURL

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.sm),
        GridItem(.flexible(), spacing: AppSpacing.sm),
    ]

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    HelpSupportProfileRowView(
                        eoaAddress: eoaAddress,
                        profileName: profileName,
                        profileAvatarURL: profileAvatarURL,
                        ensTLD: ensTLD,
                    )

                    HelpSupportCardView(
                        titleKey: "help_support_support_title",
                        systemName: "sparkles",
                        iconBackground: Color(hex: "#30D158"),
                        buttonLabelKey: "send_money_continue",
                        minHeight: 120,
                        action: { openWebURL(HelpSupportLink.supportURL) },
                    ) {
                        cardBody("help_support_support_body")
                    }

                    LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
                        HelpSupportCardView(
                            titleKey: "help_support_privacy_title",
                            systemName: "hand.raised.fill",
                            iconBackground: Color(hex: "#FF9230"),
                            buttonLabelKey: "send_money_continue",
                            minHeight: 120,
                            action: { openWebURL(HelpSupportLink.privacyURL) },
                        ) {
                            cardBody("help_support_privacy_body")
                        }

                        HelpSupportCardView(
                            titleKey: "help_support_terms_title",
                            systemName: "doc.text.fill",
                            iconBackground: Color(hex: "#0091FF"),
                            buttonLabelKey: "send_money_continue",
                            minHeight: 120,
                            action: { openWebURL(HelpSupportLink.termsURL) },
                        ) {
                            cardBody("help_support_terms_body")
                        }

                        HelpSupportCardView(
                            titleKey: "help_support_availability_title",
                            systemName: "globe",
                            iconBackground: Color(hex: "#B78A66"),
                            buttonLabelKey: "send_money_continue",
                            minHeight: 120,
                            action: { openWebURL(HelpSupportLink.availabilityURL) },
                        ) {
                            cardBody("help_support_availability_body")
                        }

                        HelpSupportCardView(
                            titleKey: "help_support_community_title",
                            systemName: "bubble.left.and.bubble.right.fill",
                            iconBackground: Color(hex: "#DB34F2"),
                            buttonLabelKey: "help_support_open",
                            minHeight: 120,
                            action: { openWebURL(HelpSupportLink.communityURL) },
                        ) {
                            cardBody("help_support_community_body")
                        }
                    }

                    HelpSupportCardView(
                        titleKey: "help_support_contact_title",
                        systemName: "envelope.fill",
                        iconBackground: Color(hex: "#FFD600"),
                    ) {
                        Text(contactText)
                            .font(AppTypography.bodyRegular)
                            .foregroundStyle(AppThemeColor.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AppButton(
                        label: "help_support_feedback",
                        variant: .outline,
                        size: .compact,
                        underlinedLabel: true,
                        foregroundColorOverride: AppThemeColor.labelSecondary,
                        action: openMailURL,
                    )
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .appNavigation(
            titleKey: "help_support_title",
            displayMode: .inline,
            hidesBackButton: false,
        )
        .appNavigationScrollEdgeStyle()
    }

    private var contactText: AttributedString {
        var text = AttributedString(String(localized: "help_support_contact_intro"))

        var email = AttributedString(HelpSupportLink.emailAddress)
        email.link = HelpSupportLink.mailURL
        email.foregroundColor = AppThemeColor.labelSecondary
        email.underlineStyle = .single

        text += email
        text += AttributedString(String(localized: "help_support_contact_outro"))
        text += AttributedString(HelpSupportLink.phoneNumber)

        return text
    }

    private func cardBody(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppTypography.bodyRegular)
            .foregroundStyle(AppThemeColor.labelSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openWebURL(_ url: URL) {
        openURL(url, prefersInApp: true)
    }

    private func openMailURL() {
        guard let mailURL = HelpSupportLink.mailURL else { return }
        openURL(mailURL)
    }
}

#Preview {
    NavigationStack {
        HelpSupportView(
            eoaAddress: "0xFFF00000000000000000000000000000BBBB",
            profileName: "nick",
            profileAvatarURL: nil,
            ensTLD: ".eth",
        )
    }
    .preferredColorScheme(.dark)
}
