import SwiftUI

struct HomeSettingsRow<Leading: View, Trailing: View>: View {
    let title: Text
    let action: (() -> Void)?
    let showsChevron: Bool
    let isDestructive: Bool
    let leading: () -> Leading
    let trailing: () -> Trailing

    init(
        title: Text,
        action: (() -> Void)? = nil,
        showsChevron: Bool = true,
        isDestructive: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
    ) {
        self.title = title
        self.action = action
        self.showsChevron = showsChevron
        self.isDestructive = isDestructive
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                leading()

                title
                    .font(.custom("Roboto-Medium", size: 15))
                    .foregroundStyle(isDestructive ? AppThemeColor.accentRed : AppThemeColor.labelPrimary)
            }

            Spacer(minLength: 0)

            trailing()

            if showsChevron {
                ChevronIcon()
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
