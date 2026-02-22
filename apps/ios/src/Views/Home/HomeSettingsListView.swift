import SwiftUI

struct HomeSettingsListView: View {
    let assetsSummaryLabel: Text
    let showWalletBackup: Bool
    let isLoggingOut: Bool
    let onPresentAssets: () -> Void
    let onProfileTap: () -> Void
    let onPreferencesTap: () -> Void
    let onWalletBackupTap: () -> Void
    let onAddressBookTap: () -> Void
    let onBeginLogout: () -> Void
    let onRefresh: () async -> Void

    private let groupedSectionGap: CGFloat = 16
    private let rowIconSize: CGFloat = 14
    private let rowBadgePadding: CGFloat = 6

    private enum HomeIconBadgeStyle {
        case solid(background: Color, icon: Color? = nil)
        case gradient(colors: [Color], icon: Color? = nil)
    }

    var body: some View {
        List {
            assetsSection
            primaryActionsSection
            logoutSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(groupedSectionGap)
        .scrollContentBackground(.hidden)
        .refreshable {
            await onRefresh()
        }
    }

    private var assetsSection: some View {
        Section {
            HomeSettingsRow(
                title: assetsSummaryLabel,
                action: onPresentAssets,
            ) {
                iconBadge(
                    systemName: "dollarsign.ring.dashed",
                    style: .solid(background: Color(UIColor(.indigo)), icon: AppThemeColor.grayWhite),
                )
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl, style: .continuous)
                    .fill(AppThemeColor.backgroundSecondary)
                    .padding(.vertical, 2),
            )
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader("home_assets_title")
                .padding(.top, groupedSectionGap)
        }
        .textCase(nil)
    }

    private var primaryActionsSection: some View {
        Section {
            HomeSettingsRow(title: Text("home_profile"), action: onProfileTap) {
                iconBadge(systemName: "person", style: .solid(background: Color(UIColor(.red)), icon: AppThemeColor.grayWhite))
            }

            HomeSettingsRow(title: Text("home_preferences"), action: onPreferencesTap) {
                iconBadge(systemName: "slider.horizontal.3", style: .solid(background: Color(UIColor(.cyan)), icon: AppThemeColor.grayWhite))
            }

            if showWalletBackup {
                HomeSettingsRow(title: Text("home_wallet_backup"), action: onWalletBackupTap) {
                    iconBadge(systemName: "wallet.bifold", style: .solid(background: Color(UIColor(.blue)), icon: AppThemeColor.grayWhite))
                }
            }

            HomeSettingsRow(title: Text("home_address_book"), action: onAddressBookTap) {
                iconBadge(systemName: "person.2", style: .solid(background: Color(UIColor(.purple)), icon: AppThemeColor.grayWhite))
            }

            HomeSettingsRow(title: Text("home_ai_agent"), action: nil, showsChevron: false) {
                iconBadge(
                    systemName: "cpu",
                    style: .gradient(colors: [Color(UIColor(.teal)), Color(UIColor(.orange))], icon: AppThemeColor.grayWhite),
                )
            }
        } header: {
            sectionHeader("home_space_title")
        }
        .textCase(nil)
    }

    private var logoutSection: some View {
        Section {
            HomeSettingsRow(
                title: Text("home_logout"),
                action: onBeginLogout,
                showsChevron: false,
                isDestructive: true,
            ) {
                Image(systemName: "circle")
                    .opacity(0)
                    .frame(width: 0)
            } trailing: {
                if isLoggingOut {
                    ProgressView()
                        .tint(AppThemeColor.accentRed)
                        .transition(.opacity)
                }
            }
            .disabled(isLoggingOut)
            .listRowBackground(
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl, style: .continuous)
                    .fill(AppThemeColor.backgroundSecondary),
            )
            .listRowSeparator(.hidden)
        }
        .textCase(nil)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelSecondary)
    }

    @ViewBuilder
    private func iconBadge(systemName: String, style: HomeIconBadgeStyle) -> some View {
        switch style {
        case let .solid(background, icon):
            IconBadge(
                style: .solid(background: background, icon: icon),
                contentPadding: rowBadgePadding,
                cornerRadius: AppCornerRadius.sm,
                borderWidth: 0,
            ) {
                Image(systemName: systemName)
                    .font(.system(size: rowIconSize, weight: .medium))
                    .frame(width: rowIconSize, height: rowIconSize)
            }
        case let .gradient(colors, icon):
            IconBadge(
                style: .gradient(colors: colors, icon: icon),
                contentPadding: rowBadgePadding,
                cornerRadius: AppCornerRadius.sm,
                borderWidth: 0,
            ) {
                Image(systemName: systemName)
                    .font(.system(size: rowIconSize, weight: .medium))
                    .frame(width: rowIconSize, height: rowIconSize)
            }
        }
    }
}
